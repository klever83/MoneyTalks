import Foundation

/// Операция по счёту.
///
/// Названо `FinanceTransaction`, а не `Transaction`, чтобы не конфликтовать с `SwiftUI.Transaction`.
public struct FinanceTransaction: Identifiable, Hashable, Codable, Sendable {
    public typealias ID = Identifier<FinanceTransaction>

    public enum Kind: String, Codable, Sendable, CaseIterable {
        case expense, income, transfer
    }

    public enum Source: String, Codable, Sendable {
        case manual, imported
    }

    public var id: ID
    public var accountID: Account.ID
    public var bookedAt: Date
    /// Сумма в валюте счёта со знаком: расход отрицательный.
    public var amount: Money
    /// Сумма в валюте покупки, если она отличается от валюты счёта.
    public var originalAmount: Money?
    public var merchantRaw: String
    public var merchantNormalized: String
    public var mcc: Int?
    public var categoryID: FinanceCategory.ID?
    /// Категорию выбрал пользователь: правила её больше не трогают.
    public var categoryLocked: Bool
    public var kind: Kind
    /// Общий идентификатор двух сторон перевода между своими счетами.
    public var transferPairID: UUID?
    public var note: String
    public var source: Source
    public var importBatchID: UUID?
    public var fingerprint: String?
    /// Операция ещё в обработке у банка (холд): при проведении следующий импорт заменит её проведённой.
    /// В остатке счёта учитывается, как и проведённая.
    public var isPending: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: ID = ID(),
        accountID: Account.ID,
        bookedAt: Date,
        amount: Money,
        originalAmount: Money? = nil,
        merchantRaw: String,
        merchantNormalized: String? = nil,
        mcc: Int? = nil,
        categoryID: FinanceCategory.ID? = nil,
        categoryLocked: Bool = false,
        kind: Kind? = nil,
        transferPairID: UUID? = nil,
        note: String = "",
        source: Source,
        importBatchID: UUID? = nil,
        fingerprint: String? = nil,
        isPending: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.accountID = accountID
        self.bookedAt = bookedAt
        self.amount = amount
        self.originalAmount = originalAmount
        self.merchantRaw = merchantRaw
        self.merchantNormalized = merchantNormalized ?? merchantRaw
        self.mcc = mcc
        self.categoryID = categoryID
        self.categoryLocked = categoryLocked
        self.kind = kind ?? (amount.isNegative ? .expense : .income)
        self.transferPairID = transferPairID
        self.note = note
        self.source = source
        self.importBatchID = importBatchID
        self.fingerprint = fingerprint
        self.isPending = isPending
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

public extension FinanceTransaction {
    /// Срок, после которого холд считается отменённым банком, если выписка за его дату его не содержит.
    static let holdExpiry: TimeInterval = 30 * 86_400

    /// Холд дольше `holdExpiry`: скорее всего, его так и не провели (или провели с другой суммой,
    /// например предавторизация на заправке), и он висит в остатке зря.
    func isStaleHold(now: Date = .now) -> Bool {
        isPending && deletedAt == nil && now.timeIntervalSince(bookedAt) >= Self.holdExpiry
    }
}
