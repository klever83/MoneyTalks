import Foundation

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
        /// Отдельное слово в названии: для коротких названий вроде `МТС` или `A1`,
        /// которые как подстрока совпали бы с чем угодно.
        case merchantWord(String)
        /// Ключ мерчанта (`MerchantNormalizer.key`) совпадает: правило «всегда так» из правки категории.
        /// `EVROOPT 123 MINSK BY` и `EVROOPT 45 GRODNO` дают один ключ.
        case merchantKey(String)
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
    public func matches(_ transaction: FinanceTransaction) -> Bool {
        switch self {
        case .merchantContains(let text):
            transaction.merchantNormalized.localizedCaseInsensitiveContains(text)
                || transaction.merchantRaw.localizedCaseInsensitiveContains(text)
        case .merchantEquals(let text):
            transaction.merchantNormalized.caseInsensitiveCompare(text) == .orderedSame
        case .merchantWord(let word):
            Self.containsWord(word, in: transaction.merchantNormalized)
                || Self.containsWord(word, in: transaction.merchantRaw)
        case .merchantKey(let key):
            MerchantNormalizer.key(transaction.merchantRaw) == key.lowercased()
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

    /// Слово окружено не буквами и не цифрами (или краями строки).
    static func containsWord(_ word: String, in text: String) -> Bool {
        func isWordCharacter(_ character: Character?) -> Bool {
            character.map { $0.isLetter || $0.isNumber } ?? false
        }
        var searchRange = text.startIndex..<text.endIndex
        while let found = text.range(of: word, options: .caseInsensitive, range: searchRange) {
            let before = found.lowerBound == text.startIndex ? nil : text[text.index(before: found.lowerBound)]
            let after = found.upperBound == text.endIndex ? nil : text[found.upperBound]
            if !isWordCharacter(before), !isWordCharacter(after) { return true }
            searchRange = text.index(after: found.lowerBound)..<text.endIndex
        }
        return false
    }
}
