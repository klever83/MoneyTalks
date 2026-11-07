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

@Suite("Встроенные правила")
struct BuiltInRulesTests {
    let categorizer = RuleCategorizer(rules: BuiltInRules.all)

    func transaction(_ merchant: String, minor: Int64 = -1000, mcc: Int? = nil) -> FinanceTransaction {
        FinanceTransaction(
            accountID: Account.ID(), bookedAt: .now,
            amount: Money(minorUnits: minor, currency: .byn),
            merchantRaw: merchant, mcc: mcc, source: .imported
        )
    }

    func key(_ merchant: String, minor: Int64 = -1000, mcc: Int? = nil) -> FinanceCategory.ID? {
        categorizer.suggest(for: transaction(merchant, minor: minor, mcc: mcc))?.categoryID
    }

    @Test("Мерчанты Беларуси", arguments: [
        ("EVROOPT 123 MINSK BY", "groceries"),
        ("Магазин ГИППО", "groceries"),
        ("YANDEX*GO 4455 MINSK", "taxi"),
        ("Пополнение МТС", "telecom"),
        ("A1 internet", "telecom"),
        ("APTEKA 12 BELFARMACIYA", "health"),
        ("NETFLIX.COM", "subscriptions"),
        ("BELARUSNEFT AZS 45", "transport"),
    ])
    func merchants(merchant: String, expected: String) {
        #expect(key(merchant) == FinanceCategory.systemID(for: expected))
    }

    @Test("Короткие названия совпадают только отдельным словом")
    func wordsNeedBoundaries() {
        #expect(key("МТСБАНК КОМИССИЯ") == nil)
        #expect(key("SA1NT SHOP") == nil)
        #expect(key("A1") == FinanceCategory.systemID(for: "telecom"))
        #expect(key("KFC Galleria") == FinanceCategory.systemID(for: "cafes"))
    }

    @Test("MCC, если мерчант неизвестен", arguments: [
        (5411, "groceries"), (5812, "cafes"), (4121, "taxi"), (5912, "health"), (4511, "travel"), (3012, "travel"),
    ])
    func mcc(code: Int, expected: String) {
        #expect(key("SOME SHOP", mcc: code) == FinanceCategory.systemID(for: expected))
    }

    @Test("Мерчант важнее MCC")
    func merchantBeatsMCC() {
        #expect(key("YANDEX GO", mcc: 5411) == FinanceCategory.systemID(for: "taxi"))
    }

    @Test("Зарплата только поступлением")
    func salaryIsIncomeOnly() {
        #expect(key("Зарплата за октябрь", minor: 150_000) == FinanceCategory.systemID(for: "salary"))
        #expect(key("Зарплата за октябрь", minor: -150_000) == nil)
    }

    @Test("ID встроенных правил уникальны и стабильны")
    func stableIDs() {
        let ids = BuiltInRules.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(BuiltInRules.all.allSatisfy { $0.origin == .builtIn })
    }
}

@Suite("Категоризация операций")
struct TransactionCategorizerTests {
    final class StubRules: CategoryRuleRepository, @unchecked Sendable {
        var stored: [CategoryRule]
        init(_ rules: [CategoryRule] = []) { stored = rules }
        func rules() async throws -> [CategoryRule] { stored }
        func save(_ rule: CategoryRule) async throws { stored.append(rule) }
        func delete(_ id: CategoryRule.ID) async throws { stored.removeAll { $0.id == id } }
    }

    let groceries = FinanceCategory.systemID(for: "groceries")
    let gifts = FinanceCategory.systemID(for: "gifts")

    func evroopt(_ change: (inout FinanceTransaction) -> Void = { _ in }) -> FinanceTransaction {
        var transaction = FinanceTransaction(
            accountID: Account.ID(), bookedAt: .now,
            amount: Money(minorUnits: -1000, currency: .byn),
            merchantRaw: "EVROOPT 123", source: .imported
        )
        change(&transaction)
        return transaction
    }

    @Test("Пустая категория заполняется, правило пользователя важнее встроенного")
    func fillsEmptyCategory() async throws {
        let builtInOnly = RuleBasedTransactionCategorizer(repository: StubRules())
        #expect(try await builtInOnly.categorize([evroopt()]).first?.categoryID == groceries)

        let userRule = CategoryRule(conditions: [.merchantContains("evroopt")], categoryID: gifts, origin: .user)
        let withUser = RuleBasedTransactionCategorizer(repository: StubRules([userRule]))
        #expect(try await withUser.categorize([evroopt()]).first?.categoryID == gifts)
    }

    @Test("Закреплённая, уже выбранная категория и переводы не меняются")
    func keepsUserChoices() async throws {
        let categorizer = RuleBasedTransactionCategorizer(repository: StubRules())
        let locked = evroopt { $0.categoryLocked = true }
        let chosen = evroopt { $0.categoryID = gifts }
        let transfer = evroopt { $0.kind = .transfer }
        let result = try await categorizer.categorize([locked, chosen, transfer])
        #expect(result[0].categoryID == nil)
        #expect(result[1].categoryID == gifts)
        #expect(result[2].categoryID == nil)
    }
}
