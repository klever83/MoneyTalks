import Categorization
import Domain
import Foundation
import Persistence
import Testing

@Suite("Управление категориями")
struct CategoryManagementTests {
    let database: AppDatabase
    let categories: GRDBCategoryRepository
    let transactions: GRDBTransactionRepository
    let accounts: GRDBAccountRepository
    let rules: GRDBCategoryRuleRepository

    init() throws {
        database = try AppDatabase.inMemory()
        categories = GRDBCategoryRepository(database: database)
        transactions = GRDBTransactionRepository(database: database)
        accounts = GRDBAccountRepository(database: database)
        rules = GRDBCategoryRuleRepository(database: database)
    }

    func category(_ name: String, parent: FinanceCategory.ID? = nil, kind: FinanceCategory.Kind = .expense) -> FinanceCategory {
        FinanceCategory(name: name, systemImage: "tag", colorHex: "#007AFF", parentID: parent, kind: kind)
    }

    @Test("Подкатегория сохраняется у категории верхнего уровня того же типа")
    func subcategory() async throws {
        let food = category("Еда")
        let lunch = category("Обеды", parent: food.id)
        try await categories.save(food)
        try await categories.save(lunch)
        let saved = try await categories.categories()
        #expect(saved.first { $0.id == lunch.id }?.parentID == food.id)
    }

    @Test("Третий уровень, другой тип и родитель самому себе запрещены")
    func invalidParents() async throws {
        let food = category("Еда")
        let lunch = category("Обеды", parent: food.id)
        try await categories.save(food)
        try await categories.save(lunch)

        await #expect(throws: CategoryError.invalidParent) {
            try await categories.save(category("Бизнес-ланчи", parent: lunch.id))
        }
        await #expect(throws: CategoryError.invalidParent) {
            try await categories.save(category("Подработка", parent: food.id, kind: .income))
        }
        var selfParent = food
        selfParent.parentID = food.id
        await #expect(throws: CategoryError.invalidParent) {
            try await categories.save(selfParent)
        }
        // У категории с подкатегориями родителя быть не может.
        let other = category("Другое")
        try await categories.save(other)
        var nested = food
        nested.parentID = other.id
        await #expect(throws: CategoryError.invalidParent) {
            try await categories.save(nested)
        }
    }

    @Test("Системную категорию можно скрыть, но не удалить")
    func systemCategories() async throws {
        let groceriesID = FinanceCategory.systemID(for: "groceries")
        await #expect(throws: CategoryError.systemCategoryCannotBeDeleted) {
            try await categories.delete(groceriesID)
        }
        var groceries = try #require(try await categories.categories().first { $0.id == groceriesID })
        groceries.isHidden = true
        try await categories.save(groceries)
        let hidden = try #require(try await categories.categories().first { $0.id == groceriesID })
        #expect(hidden.isHidden)
    }

    @Test("Удаление категории удаляет подкатегории, снимает категорию с операций и удаляет правила")
    func deleteCascades() async throws {
        let account = Account(name: "Карта", kind: .card, currency: .byn)
        try await accounts.save(account)
        let food = category("Еда")
        let lunch = category("Обеды", parent: food.id)
        try await categories.save(food)
        try await categories.save(lunch)
        let kept = FinanceCategory.systemID(for: "taxi")
        let inLunch = FinanceTransaction(
            accountID: account.id, bookedAt: .now, amount: Money(minorUnits: -500, currency: .byn),
            merchantRaw: "Столовая", categoryID: lunch.id, categoryLocked: true, source: .manual
        )
        let inTaxi = FinanceTransaction(
            accountID: account.id, bookedAt: .now, amount: Money(minorUnits: -700, currency: .byn),
            merchantRaw: "Такси", categoryID: kept, categoryLocked: true, source: .manual
        )
        try await transactions.save([inLunch, inTaxi])
        try await rules.save(CategoryRule(conditions: [.merchantKey("столовая")], categoryID: lunch.id, origin: .user))
        try await rules.save(CategoryRule(conditions: [.merchantKey("такси")], categoryID: kept, origin: .user))

        try await categories.delete(food.id)

        let remaining = try await categories.categories().map(\.id)
        #expect(!remaining.contains(food.id) && !remaining.contains(lunch.id))
        let saved = try await transactions.transactions(TransactionQuery())
        let uncategorized = try #require(saved.first { $0.id == inLunch.id })
        #expect(uncategorized.categoryID == nil && !uncategorized.categoryLocked)
        #expect(saved.first { $0.id == inTaxi.id }?.categoryID == kept)
        #expect(try await rules.rules().map(\.categoryID) == [kept])
    }

    @Test("Автокатегоризация не ставит скрытые категории")
    func hiddenCategoriesAreSkipped() async throws {
        let categorizer = RuleBasedTransactionCategorizer(repository: rules, categories: categories)
        let evroopt = FinanceTransaction(
            accountID: Account.ID(), bookedAt: .now, amount: Money(minorUnits: -500, currency: .byn),
            merchantRaw: "EVROOPT 12", source: .imported
        )
        #expect(try await categorizer.categorize([evroopt]).first?.categoryID == FinanceCategory.systemID(for: "groceries"))

        var groceries = try #require(try await categories.categories().first { $0.systemKey == "groceries" })
        groceries.isHidden = true
        try await categories.save(groceries)
        #expect(try await categorizer.categorize([evroopt]).first?.categoryID == nil)
    }
}
