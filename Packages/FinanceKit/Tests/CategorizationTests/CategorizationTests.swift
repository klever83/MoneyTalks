import Categorization
import Domain
import Foundation
import Testing

@Suite("Категоризация")
struct CategorizationTests {
    @Test("Нормализация мерчанта", arguments: [
        ("EVROOPT 123 MINSK BY", "Evroopt"),
        ("YANDEX*GO 4455 MINSK", "Yandex Go"),
        ("  Gippo  ", "Gippo"),
    ])
    func normalize(raw: String, expected: String) {
        #expect(MerchantNormalizer.normalize(raw) == expected)
    }

    @Test("Правило пользователя важнее встроенного")
    func userRuleWins() {
        let groceries = FinanceCategory.ID()
        let cafes = FinanceCategory.ID()
        let categorizer = RuleCategorizer(rules: [
            CategoryRule(conditions: [.mccRange(5411...5411)], categoryID: groceries, priority: 100, origin: .builtIn),
            CategoryRule(conditions: [.merchantContains("evroopt")], categoryID: cafes, origin: .user),
        ])
        let transaction = FinanceTransaction(
            accountID: Account.ID(), bookedAt: .now,
            amount: Money(minorUnits: -1000, currency: .byn),
            merchantRaw: "EVROOPT 123", merchantNormalized: "Evroopt", mcc: 5411, source: .imported
        )
        let suggestion = categorizer.suggest(for: transaction)
        #expect(suggestion?.categoryID == cafes)
        #expect(suggestion?.confidence == 1)
    }

    @Test("Без совпадений подсказки нет")
    func noMatch() {
        let categorizer = RuleCategorizer(rules: [
            CategoryRule(conditions: [.merchantEquals("Gippo")], categoryID: FinanceCategory.ID(), origin: .builtIn),
        ])
        let transaction = FinanceTransaction(
            accountID: Account.ID(), bookedAt: .now,
            amount: Money(minorUnits: -1000, currency: .byn), merchantRaw: "Santa", source: .manual
        )
        #expect(categorizer.suggest(for: transaction) == nil)
    }
}
