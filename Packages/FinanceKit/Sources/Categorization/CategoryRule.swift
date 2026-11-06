import Domain

/// Правило автокатегоризации: все условия должны выполниться.
public struct CategoryRule: Identifiable, Hashable, Codable, Sendable {
    public typealias ID = Identifier<CategoryRule>

    public enum Sign: String, Codable, Sendable {
        case negative, positive
    }

    public enum Origin: String, Codable, Sendable {
        /// Создано пользователем (в том числе из правки категории). Всегда важнее встроенных.
        case user
        case builtIn
    }

    public enum Condition: Hashable, Codable, Sendable {
        case merchantContains(String)
        case merchantEquals(String)
        case mccRange(ClosedRange<Int>)
        case amountSign(Sign)
        case account(Account.ID)
    }

    public var id: ID
    public var conditions: [Condition]
    public var categoryID: FinanceCategory.ID
    public var priority: Int
    public var origin: Origin

    public init(
        id: ID = ID(),
        conditions: [Condition],
        categoryID: FinanceCategory.ID,
        priority: Int = 0,
        origin: Origin
    ) {
        self.id = id
        self.conditions = conditions
        self.categoryID = categoryID
        self.priority = priority
        self.origin = origin
    }

    public func matches(_ transaction: FinanceTransaction) -> Bool {
        !conditions.isEmpty && conditions.allSatisfy { $0.matches(transaction) }
    }
}

extension CategoryRule.Condition {
    func matches(_ transaction: FinanceTransaction) -> Bool {
        switch self {
        case .merchantContains(let text):
            transaction.merchantNormalized.localizedCaseInsensitiveContains(text)
                || transaction.merchantRaw.localizedCaseInsensitiveContains(text)
        case .merchantEquals(let text):
            transaction.merchantNormalized.caseInsensitiveCompare(text) == .orderedSame
        case .mccRange(let range):
            transaction.mcc.map(range.contains) ?? false
        case .amountSign(.negative):
            transaction.amount.isNegative
        case .amountSign(.positive):
            !transaction.amount.isNegative && !transaction.amount.isZero
        case .account(let id):
            transaction.accountID == id
        }
    }
}
