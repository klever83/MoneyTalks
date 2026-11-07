import DesignSystem
import Domain
import SwiftUI

@MainActor
@Observable
final class CategoriesViewModel {
    private(set) var categories: [FinanceCategory] = []
    var errorMessage: String?
    private let repository: any CategoryRepository

    init(repository: any CategoryRepository) {
        self.repository = repository
    }

    /// Категории типа деревом: родитель, за ним подкатегории.
    func tree(of kind: FinanceCategory.Kind) -> [(category: FinanceCategory, depth: Int)] {
        FinanceCategory.tree(categories.filter { $0.kind == kind })
    }

    /// Возможные родители: неудалённые категории верхнего уровня того же типа, кроме самой категории.
    /// У категории со своими подкатегориями родителя быть не может (только два уровня).
    func parentCandidates(for category: FinanceCategory) -> [FinanceCategory] {
        guard !hasChildren(category) else { return [] }
        return categories.filter { $0.kind == category.kind && $0.parentID == nil && $0.id != category.id }
    }

    func hasChildren(_ category: FinanceCategory) -> Bool {
        categories.contains { $0.parentID == category.id }
    }

    /// Заготовка новой категории: в конец списка, с цветом и иконкой по умолчанию.
    func newCategory(kind: FinanceCategory.Kind) -> FinanceCategory {
        FinanceCategory(
            name: "",
            systemImage: CategoryAppearance.symbols[0],
            colorHex: CategoryAppearance.colors[categories.count % CategoryAppearance.colors.count],
            kind: kind,
            sortOrder: (categories.map(\.sortOrder).max() ?? 0) + 1
        )
    }

    func observe() async {
        do {
            for try await items in repository.observeCategories() {
                categories = items
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func save(_ category: FinanceCategory) async -> Bool {
        var category = category
        category.name = category.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !category.name.isEmpty else { return false }
        do {
            try await repository.save(category)
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    func setHidden(_ hidden: Bool, _ category: FinanceCategory) async {
        var category = category
        category.isHidden = hidden
        await save(category)
    }

    func delete(_ category: FinanceCategory) async {
        do {
            try await repository.delete(category.id)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    static func message(for error: any Error) -> String {
        switch error {
        case CategoryError.systemCategoryCannotBeDeleted:
            String(localized: "Системную категорию нельзя удалить, её можно скрыть.")
        case CategoryError.invalidParent:
            String(localized: "Подкатегории бывают только у категорий верхнего уровня того же типа.")
        default:
            error.localizedDescription
        }
    }
}

/// Список категорий: создание, правка, подкатегории, скрытие системных и удаление своих.
public struct CategoriesScreen: View {
    @State private var model: CategoriesViewModel
    @State private var editing: FinanceCategory?
    @State private var categoryToDelete: FinanceCategory?

    public init(repository: any CategoryRepository) {
        _model = State(initialValue: CategoriesViewModel(repository: repository))
    }

    public var body: some View {
        List {
            section("Расходы", kind: .expense)
            section("Доходы", kind: .income)
        }
        .navigationTitle("Категории")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Категория расходов") { editing = model.newCategory(kind: .expense) }
                    Button("Категория доходов") { editing = model.newCategory(kind: .income) }
                } label: {
                    Label("Добавить", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editing) { category in
            CategoryEditor(
                category: category,
                isNew: !model.categories.contains { $0.id == category.id },
                parents: model.parentCandidates(for: category)
            ) { edited in
                await model.save(edited)
            }
        }
        .confirmationDialog(
            "Удалить категорию?",
            isPresented: Binding(get: { categoryToDelete != nil }, set: { if !$0 { categoryToDelete = nil } }),
            titleVisibility: .visible,
            presenting: categoryToDelete
        ) { category in
            Button("Удалить", role: .destructive) {
                Task { await model.delete(category) }
            }
        } message: { category in
            Text(model.hasChildren(category)
                ? "Подкатегории тоже удалятся. Их операции останутся без категории."
                : "Операции этой категории останутся без категории.")
        }
        .errorAlert($model.errorMessage)
        .task { await model.observe() }
    }

    private func section(_ title: LocalizedStringKey, kind: FinanceCategory.Kind) -> some View {
        Section(title) {
            ForEach(model.tree(of: kind), id: \.category.id) { item in
                Button {
                    editing = item.category
                } label: {
                    CategoryRow(category: item.category, depth: item.depth)
                }
                .foregroundStyle(.primary)
                .swipeActions {
                    if item.category.isSystem {
                        Button(
                            item.category.isHidden ? "Показать" : "Скрыть",
                            systemImage: item.category.isHidden ? "eye" : "eye.slash"
                        ) {
                            Task { await model.setHidden(!item.category.isHidden, item.category) }
                        }
                    } else {
                        Button("Удалить", systemImage: "trash", role: .destructive) {
                            categoryToDelete = item.category
                        }
                    }
                }
            }
        }
    }
}

private struct CategoryRow: View {
    let category: FinanceCategory
    let depth: Int

    var body: some View {
        Label {
            HStack {
                Text(category.displayName)
                Spacer()
                if category.isHidden {
                    Image(systemName: "eye.slash")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Скрыта")
                }
            }
        } icon: {
            Image(systemName: category.systemImage)
                .foregroundStyle(category.color)
        }
        .padding(.leading, depth > 0 ? 24 : 0)
        .opacity(category.isHidden ? 0.5 : 1)
    }
}
