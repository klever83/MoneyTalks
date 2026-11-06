import Domain
import Foundation

/// Снятие наличных — не расход, а перевод с карты в кошелёк «Наличные» в валюте снятия.
/// Траты наличными пользователь вносит в кошелёк сам. Внесение наличных через банкомат —
/// обратный перевод, из кошелька на карту.
///
/// Вызывается при импорте до `TransferMatcher`: операции с наличными становятся переводом
/// со своей парой в кошельке, и поиск переводов между картами их уже не трогает.
public enum CashWithdrawals {
    /// MCC выдачи наличных: в отделении банка и в банкомате.
    static let cashMCC: Set<Int> = [6010, 6011]

    /// Операция с наличными: по MCC или по типу операции в описании банка.
    /// Комиссия за снятие или перевод — расход, а не сама операция, даже с MCC банкомата.
    /// «NO FEE» в описании P2P Приорбанка значит обратное и комиссией не считается.
    public static func isFee(_ text: String) -> Bool {
        let lowered = text.lowercased().replacingOccurrences(of: "no fee", with: "")
        return lowered.contains("комисс") || lowered.contains("плата за") || lowered.contains(/\bfee\b/)
    }

    public static func isCashOperation(_ transaction: FinanceTransaction) -> Bool {
        if isFee(transaction.merchantRaw) { return false }
        if let mcc = transaction.mcc, cashMCC.contains(mcc) { return true }
        let text = transaction.merchantRaw
        // Приорбанк: тип операции в начале описания, `ATM BLR GOMEL …`, `Cash BLR Minsk Dop.ofis …`.
        if text.contains(/^(?:ATM|Cash)\s/) { return true }
        let lowered = text.lowercased()
        return ["выдача наличных", "снятие наличных", "получение денег в банкомате", "взнос наличных", "внесение наличных"]
            .contains { lowered.contains($0) }
    }

    /// Кошелёк для наличных в валюте: свой счёт «Наличные» пользователя, если он уже есть,
    /// иначе новый с постоянным идентификатором (тот же на любом устройстве). Если кошелёк с этим
    /// идентификатором пользователь удалил, новый получает случайный: удалённый не воскрешается.
    /// - Parameter deletedIDs: удалённые счета, если их нет в `accounts`.
    public static func wallet(
        for currency: Currency,
        among accounts: [Account],
        deletedIDs: Set<Account.ID> = [],
        name: String,
        now: Date = .now
    ) -> Account {
        if let existing = accounts.first(where: { $0.kind == .cash && $0.currency == currency && $0.deletedAt == nil }) {
            return existing
        }
        let stableID = Account.ID(UUID(v5: "cash-wallet|\(currency.code)", namespace: namespace))
        return Account(
            id: accounts.contains { $0.id == stableID } || deletedIDs.contains(stableID) ? Account.ID() : stableID,
            name: name,
            kind: .cash,
            currency: currency,
            createdAt: now,
            updatedAt: now
        )
    }

    /// Операции с наличными становятся переводом, а в кошельке появляется вторая сторона.
    /// - Parameter wallet: счёт-кошелёк для валюты снятых наличных.
    /// - Returns: все операции (с отмеченными переводами) и новые операции кошелька.
    public static func pair(
        _ transactions: [FinanceTransaction],
        wallet: (Currency) -> Account.ID,
        now: Date = .now
    ) -> (transactions: [FinanceTransaction], walletTransactions: [FinanceTransaction]) {
        var created: [FinanceTransaction] = []
        let updated = transactions.map { transaction -> FinanceTransaction in
            guard transaction.deletedAt == nil,
                  transaction.transferPairID == nil,
                  transaction.kind != .transfer,
                  !transaction.categoryLocked,
                  !transaction.amount.isZero,
                  isCashOperation(transaction)
            else { return transaction }

            // Наличные в валюте операции: снятие евро с рублёвой карты кладёт в кошелёк евро.
            let cash = (transaction.originalAmount.map { $0.absolute } ?? transaction.amount.absolute)
            let walletAmount = transaction.amount.isNegative ? cash : cash.negated
            let pairID = UUID(v5: "cash|\(transaction.id.rawValue.uuidString)", namespace: namespace)
            created.append(FinanceTransaction(
                id: FinanceTransaction.ID(UUID(v5: "cash-side|\(transaction.id.rawValue.uuidString)", namespace: namespace)),
                accountID: wallet(cash.currency),
                bookedAt: transaction.bookedAt,
                amount: walletAmount,
                merchantRaw: transaction.merchantRaw,
                merchantNormalized: transaction.merchantNormalized,
                mcc: transaction.mcc,
                kind: .transfer,
                transferPairID: pairID,
                source: transaction.source,
                importBatchID: transaction.importBatchID,
                fingerprint: transaction.fingerprint.map { "cash:" + $0 },
                createdAt: now,
                updatedAt: now
            ))
            var transfer = transaction
            transfer.kind = .transfer
            transfer.transferPairID = pairID
            transfer.categoryID = nil
            transfer.updatedAt = now
            return transfer
        }
        return (updated, created)
    }

    static let namespace = UUID(uuidString: "0E7A4C61-5B2D-4F8E-A913-7C4D2B6E9F10")!
}
