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

    func categories(of kind: FinanceCategory.Kind) -> [FinanceCategory] {
        categories.filter { $0.kind == kind }
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
}

/// Список категорий. Создание, редактирование и правила — следующие задачи.
public struct CategoriesScreen: View {
    @State private var model: CategoriesViewModel

    public init(repository: any CategoryRepository) {
        _model = State(initialValue: CategoriesViewModel(repository: repository))
    }

    public var body: some View {
        List {
            Section("Расходы") {
                ForEach(model.categories(of: .expense)) { CategoryRow(category: $0) }
            }
            Section("Доходы") {
                ForEach(model.categories(of: .income)) { CategoryRow(category: $0) }
            }
        }
        .navigationTitle("Категории")
        .errorAlert($model.errorMessage)
        .task { await model.observe() }
    }
}

private struct CategoryRow: View {
    let category: FinanceCategory

    var body: some View {
        Label {
            Text(category.displayName)
        } icon: {
            Image(systemName: category.systemImage)
                .foregroundStyle(category.color)
        }
    }
}
