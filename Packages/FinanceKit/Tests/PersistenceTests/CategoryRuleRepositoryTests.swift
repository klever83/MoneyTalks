import Categorization
import Domain
import Foundation
import Persistence
import Testing

@Suite("Правила категоризации в базе")
struct CategoryRuleRepositoryTests {
    let database: AppDatabase
    let rules: GRDBCategoryRuleRepository
    let categories: GRDBCategoryRepository

    init() throws {
        database = try AppDatabase.inMemory()
        rules = GRDBCategoryRuleRepository(database: database)
        categories = GRDBCategoryRepository(database: database)
    }

    @Test("Правило сохраняется со всеми условиями и удаляется мягко")
    func roundTrip() async throws {
        let account = Account.ID()
        let rule = CategoryRule(
            conditions: [
                .merchantContains("Евроопт"), .merchantEquals("Evroopt"), .merchantWord("МТС"),
                .mccRange(5411...5499), .amountSign(.negative), .account(account),
            ],
            categoryID: FinanceCategory.systemID(for: "groceries"),
            priority: 7,
            origin: .user
        )
        try await rules.save(rule)
        #expect(try await rules.rules() == [rule])

        var changed = rule
        changed.priority = 9
        try await rules.save(changed)
        #expect(try await rules.rules() == [changed])

        try await rules.delete(rule.id)
        #expect(try await rules.rules().isEmpty)
    }

    @Test("Каждое встроенное правило ведёт в существующую системную категорию")
    func builtInRulesPointToSystemCategories() async throws {
        let ids = Set(try await categories.categories().map(\.id))
        for rule in BuiltInRules.all {
            #expect(ids.contains(rule.categoryID), "Нет категории для правила \(rule.conditions)")
        }
    }
}
