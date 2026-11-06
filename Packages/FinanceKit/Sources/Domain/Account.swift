import Foundation

/// Счёт: карта, текущий счёт, вклад или наличные.
public struct Account: Identifiable, Hashable, Codable, Sendable {
    public typealias ID = Identifier<Account>

    public enum Kind: String, Codable, Sendable, CaseIterable {
        case card, current, savings, cash
    }

    public var id: ID
    public var name: String
    public var kind: Kind
    public var currency: Currency
    /// Идентификатор банка из реестра парсеров, например `by.belarusbank`. У наличных — `nil`.
    public var bankID: String?
    /// Последние цифры карты или счёта для сопоставления с выпиской, например `•• 1234`.
    public var maskedNumber: String?
    public var openingBalance: Money
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: ID = ID(),
        name: String,
        kind: Kind,
        currency: Currency,
        bankID: String? = nil,
        maskedNumber: String? = nil,
        openingBalance: Money? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.currency = currency
        self.bankID = bankID
        self.maskedNumber = maskedNumber
        self.openingBalance = openingBalance ?? .zero(currency)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
