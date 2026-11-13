import Domain
import Foundation

/// Операции в обработке (холды) при импорте.
///
/// Холд импортируется как обычная операция с отметкой `isPending` и сразу входит в остаток счёта:
/// так остаток в приложении совпадает с банковским, который холды уже учитывает. Когда операция
/// проведена, следующая выписка приносит её проведённой, иногда с другой суммой в валюте счёта
/// (пересчёт курса), и холд заменяется ею, а не дублируется. Холд, которого нет в выписке спустя
/// `expiry`, банк отменил: он тоже снимается.
public enum HoldMatcher {
    /// Проведённая операция приходит не раньше дня до холда и не позже этого срока после него.
    public static let window: TimeInterval = 14 * 86_400
    /// Холд, который выписка за его дату не содержит ни в каком виде и с даты которого прошёл
    /// этот срок, считается отменённым банком.
    static let expiry = FinanceTransaction.holdExpiry

    public struct Resolution: Sendable, Equatable {
        /// Сохранённые холды, которые провелись в этой выписке: проведённая операция → холд.
        public var replaced: [FinanceTransaction.ID: FinanceTransaction] = [:]
        /// Сохранённые холды, отменённые банком.
        public var cancelled: [FinanceTransaction] = []
        /// Новые холды, которые уже сохранены проведёнными (выписка старше уже загруженной).
        public var alreadyPosted: Set<FinanceTransaction.ID> = []
    }

    /// Проведённая операция подходит холду: тот же знак, та же сумма в валюте счёта или в валюте
    /// покупки, дата в окне.
    static func matches(hold: FinanceTransaction, posted: FinanceTransaction) -> Bool {
        guard hold.accountID == posted.accountID,
              hold.amount.isNegative == posted.amount.isNegative
        else { return false }
        let offset = posted.bookedAt.timeIntervalSince(hold.bookedAt)
        guard offset >= -86_400, offset <= window else { return false }
        if hold.amount == posted.amount { return true }
        if let original = hold.originalAmount, original == posted.originalAmount { return true }
        return false
    }

    /// - Parameters:
    ///   - new: новые операции выписки (после отсева дублей).
    ///   - existing: сохранённые неудалённые операции счёта вокруг дат выписки (с запасом `window`).
    ///   - statementFingerprints: отпечатки всех строк выписки, включая дубли: холд, который
    ///     выписка всё ещё показывает в обработке, не отменён.
    ///   - period: период выписки.
    public static func resolve(
        new: [FinanceTransaction],
        existing: [FinanceTransaction],
        statementFingerprints: Set<String>,
        period: DateInterval?
    ) -> Resolution {
        var resolution = Resolution()
        // Одна выписка не показывает одну операцию дважды: холд, который она всё ещё показывает
        // в обработке, не проведён её же строками (соседняя поездка в метро на ту же сумму — другая операция).
        let inStatement = { (transaction: FinanceTransaction) in
            transaction.fingerprint.map(statementFingerprints.contains) ?? false
        }
        let holds = existing.filter { $0.isPending && $0.deletedAt == nil && !inStatement($0) }
        let posted = new.filter { !$0.isPending }
        for (hold, transaction) in pairs(holds, posted) {
            resolution.replaced[transaction.id] = hold
        }

        let replacedIDs = Set(resolution.replaced.values.map(\.id))
        if let period {
            resolution.cancelled = holds.filter { hold in
                !replacedIDs.contains(hold.id)
                    && period.contains(hold.bookedAt)
                    && period.end.timeIntervalSince(hold.bookedAt) >= expiry
            }
        }

        // Выписка старше уже загруженной: её холды давно проведены и сохранены. Проведённая операция,
        // которую показывает эта же выписка, — не версия её холда, а другая операция.
        let savedPosted = existing.filter {
            !$0.isPending && $0.deletedAt == nil && $0.source == .imported && !inStatement($0)
        }
        let newHolds = new.filter(\.isPending)
        resolution.alreadyPosted = Set(pairs(newHolds, savedPosted).map(\.hold.id))
        return resolution
    }

    /// Пары «холд — проведённая операция» один к одному: сначала с тем же описанием, потом ближайшие по дате.
    static func pairs(
        _ holds: [FinanceTransaction], _ posted: [FinanceTransaction]
    ) -> [(hold: FinanceTransaction, posted: FinanceTransaction)] {
        struct Edge {
            var hold: Int
            var posted: Int
            var sameMerchant: Bool
            var distance: TimeInterval
        }
        var edges: [Edge] = []
        for (h, hold) in holds.enumerated() {
            for (p, transaction) in posted.enumerated() where matches(hold: hold, posted: transaction) {
                edges.append(Edge(
                    hold: h,
                    posted: p,
                    sameMerchant: hold.merchantNormalized.lowercased() == transaction.merchantNormalized.lowercased(),
                    distance: abs(transaction.bookedAt.timeIntervalSince(hold.bookedAt))
                ))
            }
        }
        // Порядок при равенстве фиксирован: пересчёт превью даёт те же пары.
        edges.sort { lhs, rhs in
            if lhs.sameMerchant != rhs.sameMerchant { return lhs.sameMerchant }
            if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
            return (lhs.hold, lhs.posted) < (rhs.hold, rhs.posted)
        }
        var usedHolds = Set<Int>()
        var usedPosted = Set<Int>()
        var result: [(hold: FinanceTransaction, posted: FinanceTransaction)] = []
        for edge in edges where !usedHolds.contains(edge.hold) && !usedPosted.contains(edge.posted) {
            usedHolds.insert(edge.hold)
            usedPosted.insert(edge.posted)
            result.append((holds[edge.hold], posted[edge.posted]))
        }
        return result
    }
}
