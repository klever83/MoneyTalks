import Domain
@testable import FeatureCategories
import Foundation
import Persistence
import Testing

@MainActor
@Suite("Категории: view model")
struct CategoriesViewModelTests {
    let rules: GRDBCategoryRuleRepository
    let model: CategoriesViewModel
    let groceries = FinanceCategory.systemID(for: "groceries")

    init() throws {
        let database = try AppDatabase.inMemory()
        rules = GRDBCategoryRuleRepository(database: database)
        model = CategoriesViewModel(repository: GRDBCategoryRepository(database: database), rules: rules)
    }

    /// Ждёт, пока поток `observe` доставит нужное состояние.
    func waitUntil(_ condition: () -> Bool) async throws {
        var attempts = 0
        while !condition(), attempts < 500 {
            try await Task.sleep(for: .milliseconds(10))
            attempts += 1
        }
        #expect(condition())
    }

    func category(named name: String) -> FinanceCategory? {
        model.categories.first { $0.name == name }
    }

    @Test("Новая категория: имя без пробелов по краям, пустое имя не сохраняется, порядок в конце")
    func create() async throws {
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        try await waitUntil { !model.categories.isEmpty }
        let maxOrder = try #require(model.categories.map(\.sortOrder).max())

        var blank = model.newCategory(kind: .expense)
        blank.name = "   "
        #expect(await !model.save(blank))

        var pets = model.newCategory(kind: .expense)
        #expect(pets.sortOrder == maxOrder + 1)
        pets.name = "  Питомцы \n"
        #expect(await model.save(pets))
        try await waitUntil { category(named: "Питомцы") != nil }
        #expect(model.errorMessage == nil)
    }

    @Test("Подкатегории: дерево, кандидаты в родители, скрытие вместе с родителем, неверный родитель")
    func subcategories() async throws {
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        try await waitUntil { !model.categories.isEmpty }
        let parent = try #require(model.categories.first { $0.id == groceries })

        var child = model.newCategory(kind: .expense)
        child.name = "Фрукты"
        child.parentID = parent.id
        #expect(await model.save(child))
        try await waitUntil { category(named: "Фрукты") != nil }

        let tree = model.tree(of: .expense)
        let parentIndex = try #require(tree.firstIndex { $0.category.id == parent.id })
        #expect(tree[parentIndex + 1].category.id == child.id)
        #expect(tree[parentIndex + 1].depth == 1)

        // У категории с подкатегориями родителя быть не может; подкатегория выбирает среди верхнего уровня.
        #expect(model.hasChildren(parent))
        #expect(model.parentCandidates(for: parent).isEmpty)
        let candidates = model.parentCandidates(for: child)
        #expect(candidates.contains { $0.id == parent.id })
        #expect(candidates.allSatisfy { $0.parentID == nil && $0.kind == .expense && $0.id != child.id })

        await model.setHidden(true, parent)
        try await waitUntil { model.hiddenIDs.contains(parent.id) }
        #expect(model.hiddenIDs.contains(child.id))

        // Доход не может быть подкатегорией расхода.
        var income = model.newCategory(kind: .income)
        income.name = "Подработка"
        income.parentID = parent.id
        #expect(await !model.save(income))
        #expect(model.errorMessage == "Подкатегории бывают только у категорий верхнего уровня того же типа.")
    }

    @Test("Удаление: системную нельзя, своя уходит вместе с подкатегориями и правилами")
    func delete() async throws {
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        try await waitUntil { !model.categories.isEmpty }

        await model.delete(try #require(model.categories.first { $0.id == groceries }))
        #expect(model.errorMessage == "Системную категорию нельзя удалить, её можно скрыть.")
        model.errorMessage = nil

        var hobby = model.newCategory(kind: .expense)
        hobby.name = "Хобби"
        #expect(await model.save(hobby))
        var child = model.newCategory(kind: .expense)
        child.name = "Рыбалка"
        child.parentID = hobby.id
        #expect(await model.save(child))
        let rule = CategoryRule(conditions: [.merchantContains("rybolov")], categoryID: hobby.id, origin: .user)
        try await rules.save(rule)
        await model.loadRules()
        #expect(model.rules(for: hobby).map(\.id) == [rule.id])
        try await waitUntil { category(named: "Рыбалка") != nil }

        await model.delete(hobby)
        #expect(model.errorMessage == nil)
        try await waitUntil { category(named: "Хобби") == nil && category(named: "Рыбалка") == nil }
        #expect(model.rules(for: hobby).isEmpty)
    }

    @Test("Удаление правила убирает его из списка")
    func deleteRule() async throws {
        let rule = CategoryRule(conditions: [.merchantContains("evroopt")], categoryID: groceries, origin: .user)
        try await rules.save(rule)
        await model.loadRules()
        #expect(model.rules.map(\.id) == [rule.id])

        await model.deleteRule(rule)
        #expect(model.rules.isEmpty)
        #expect(try await rules.rules().isEmpty)
    }
}
