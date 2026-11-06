import Domain
import Foundation

/// Поиск переводов между своими счетами: списание с одного счёта и зачисление на другой.
/// Такие операции не доход и не расход, поэтому обе стороны получают `kind = .transfer`
/// и общий `transferPairID`, а аналитика их пропускает.
///
/// Пара — это списание и зачисление на ту же сумму в пределах окна по времени:
/// - между разными счетами: одна валюта и равные суммы, либо обмен валют, когда сумма
///   в валюте операции одной стороны равна сумме другой (`originalAmount`);
/// - внутри одного счёта (например, контракт и карта Приорбанка): равные суммы в тот же день
///   и общий номер документа в описании. Без номера это обычно покупка и её возврат, не перевод.
///
/// Совпадение суммы само по себе ничего не доказывает (заправка на 50 BYN и перевод от друга
/// на 50 BYN), поэтому обе стороны должны выглядеть как перевод: в описании есть «перевод»,
/// P2P, пополнение и т. п., а MCC, если банк его дал, не MCC покупки.
///
/// Неоднозначные случаи не склеиваются: если у операции две равноудалённые пары на разных счетах,
/// лучше оставить обе как есть, чем угадать неверно. Операции с категорией, выбранной
/// пользователем, удалённые и уже связанные не трогаются.
public enum TransferMatcher {
    public struct Pair: Hashable, Sendable {
        public var outgoing: FinanceTransaction.ID
        public var incoming: FinanceTransaction.ID
        /// Общий идентификатор пары: одинаковый при повторном поиске на любом устройстве.
        public var id: UUID

        public init(outgoing: FinanceTransaction.ID, incoming: FinanceTransaction.ID) {
            self.outgoing = outgoing
            self.incoming = incoming
            id = UUID(
                v5: "\(outgoing.rawValue.uuidString)|\(incoming.rawValue.uuidString)",
                namespace: TransferMatcher.namespace
            )
        }
    }

    static let namespace = UUID(uuidString: "6B1C2E8A-0F4D-4E7B-9C35-2A9D8E51F0C7")!

    /// Окно между сторонами перевода на разных счетах: банки отражают зачисление с задержкой.
    public static let defaultWindow: TimeInterval = 3 * 86_400
    /// Внутри одного счёта стороны перевода приходят одним днём.
    static let sameAccountWindow: TimeInterval = 86_400
    /// Разница во времени меньше этой считается одинаковой при проверке неоднозначности.
    static let tieTolerance: TimeInterval = 60

    /// Пары переводов среди операций. Порядок операций не важен.
    public static func pairs(in transactions: [FinanceTransaction], window: TimeInterval = defaultWindow) -> [Pair] {
        let candidates = transactions.filter { transaction in
            transaction.deletedAt == nil
                && transaction.transferPairID == nil
                && !transaction.categoryLocked
                && transaction.kind != .transfer
                && !transaction.amount.isZero
                && looksLikeTransfer(transaction)
        }
        let outgoing = candidates.filter(\.amount.isNegative)
        let incoming = candidates.filter { !$0.amount.isNegative }

        struct Edge {
            var outgoing: Int
            var incoming: Int
            var distance: TimeInterval
        }
        var edges: [Edge] = []
        for (o, out) in outgoing.enumerated() {
            for (i, into) in incoming.enumerated() {
                let distance = abs(into.bookedAt.timeIntervalSince(out.bookedAt))
                if matches(out, into, distance: distance, window: window) {
                    edges.append(Edge(outgoing: o, incoming: i, distance: distance))
                }
            }
        }
        edges.sort { $0.distance < $1.distance }

        var usedOutgoing = Set<Int>()
        var usedIncoming = Set<Int>()
        var result: [Pair] = []
        for edge in edges where !usedOutgoing.contains(edge.outgoing) && !usedIncoming.contains(edge.incoming) {
            // Та же операция с другой стороны так же близко, но на другом счёте: не угадываем.
            let ambiguous = edges.contains { other in
                guard abs(other.distance - edge.distance) < tieTolerance else { return false }
                if other.outgoing == edge.outgoing, other.incoming != edge.incoming, !usedIncoming.contains(other.incoming) {
                    return incoming[other.incoming].accountID != incoming[edge.incoming].accountID
                }
                if other.incoming == edge.incoming, other.outgoing != edge.outgoing, !usedOutgoing.contains(other.outgoing) {
                    return outgoing[other.outgoing].accountID != outgoing[edge.outgoing].accountID
                }
                return false
            }
            guard !ambiguous else { continue }
            usedOutgoing.insert(edge.outgoing)
            usedIncoming.insert(edge.incoming)
            result.append(Pair(outgoing: outgoing[edge.outgoing].id, incoming: incoming[edge.incoming].id))
        }
        return result
    }

    /// Операции с отмеченными парами: обе стороны становятся переводом с общим `transferPairID`.
    public static func apply(_ pairs: [Pair], to transactions: [FinanceTransaction], now: Date = .now) -> [FinanceTransaction] {
        var pairByTransaction: [FinanceTransaction.ID: UUID] = [:]
        for pair in pairs {
            pairByTransaction[pair.outgoing] = pair.id
            pairByTransaction[pair.incoming] = pair.id
        }
        return transactions.map { transaction in
            guard let pairID = pairByTransaction[transaction.id] else { return transaction }
            var transfer = transaction
            transfer.kind = .transfer
            transfer.transferPairID = pairID
            transfer.categoryID = nil
            transfer.updatedAt = now
            return transfer
        }
    }

    // MARK: - Правила

    private static func matches(
        _ out: FinanceTransaction,
        _ into: FinanceTransaction,
        distance: TimeInterval,
        window: TimeInterval
    ) -> Bool {
        if out.accountID == into.accountID {
            return distance <= sameAccountWindow
                && into.amount == out.amount.absolute
                && !references(out.merchantRaw).isDisjoint(with: references(into.merchantRaw))
        }
        guard distance <= window else { return false }
        if into.amount == out.amount.absolute { return true }
        // Обмен валют: одна из сторон знает сумму в валюте другой.
        if let original = out.originalAmount, original.absolute == into.amount { return true }
        if let original = into.originalAmount, original.absolute == out.amount.absolute { return true }
        return false
    }

    /// MCC, с которыми операция может быть переводом: денежные переводы, финансовые учреждения,
    /// пополнение и выдача средств. Остальные MCC — покупки.
    static let transferMCC: Set<Int> = [4829, 6010, 6011, 6012, 6051, 6538, 6540]

    /// Слова, по которым банки помечают переводы между счетами и картами.
    static let transferWords = [
        "перевод", "p2p", "пополнение", "поступление на контракт", "payment from", "обмен", "конверс",
        "transfer", "popolnenie",
    ]

    static func looksLikeTransfer(_ transaction: FinanceTransaction) -> Bool {
        if let mcc = transaction.mcc, !transferMCC.contains(mcc) { return false }
        if CashWithdrawals.isFee(transaction.merchantRaw) { return false }
        let text = transaction.merchantRaw.lowercased()
        return transferWords.contains { text.contains($0) }
    }

    /// Номера документов в описании: от шести цифр, можно через дефис (`000000-00000-000001`).
    static func references(_ text: String) -> Set<String> {
        Set(text.matches(of: /\d[\d-]{4,}\d/).compactMap { match in
            let token = String(match.output)
            return token.filter(\.isNumber).count >= 6 ? token : nil
        })
    }
}
