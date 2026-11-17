import Categorization
import DesignSystem
import Domain
import SwiftUI

/// Операции без категории, сгруппированные по мерчанту. Живёт в `TransactionsViewModel`,
/// чтобы список операций показывал, сколько их осталось.
@MainActor
@Observable
final class UncategorizedViewModel {
    private(set) var groups: [UncategorizedReview.Group] = []
    /// Все операции: правило «всегда так» раскладывает и те, что не попали в группу.
    private var all: [FinanceTransaction] = []
    var errorMessage: String?

    private let transactionRepository: any TransactionRepository
    private let ruleRepository: any CategoryRuleRepository

    init(transactions: any TransactionRepository, rules: any CategoryRuleRepository) {
        transactionRepository = transactions
        ruleRepository = rules
    }

    var count: Int { groups.reduce(0) { $0 + $1.transactions.count } }
    var merchants: [UncategorizedReview.Group] { groups.filter(\.canCreateRule) }
    var singles: [UncategorizedReview.Group] { groups.filter { !$0.canCreateRule } }

    func observe() async {
        do {
            for try await items in transactionRepository.observeTransactions(TransactionQuery()) {
                all = items
                groups = UncategorizedReview.groups(items)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func assign(_ group: UncategorizedReview.Group, to categoryID: FinanceCategory.ID, always: Bool) async {
        do {
            let assignment = UncategorizedReview.assign(
                group, to: categoryID, always: always,
                rules: try await ruleRepository.rules(),
                transactions: all
            )
            if let rule = assignment.rule {
                try await ruleRepository.save(rule)
            }
            try await transactionRepository.save(assignment.updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Экран «Без категории»: мерчант за мерчантом, категория в одно касание.
struct UncategorizedScreen: View {
    let model: TransactionsViewModel
    @State private var selected: UncategorizedReview.Group?

    private var review: UncategorizedViewModel { model.review }

    var body: some View {
        List {
            if !review.merchants.isEmpty {
                Section {
                    ForEach(review.merchants) { group in
                        Button { selected = group } label: { UncategorizedGroupRow(group: group) }
                    }
                } header: {
                    Text("По мерчантам")
                } footer: {
                    Text("Категория применится ко всем операциям мерчанта.")
                }
            }
            if !review.singles.isEmpty {
                Section {
                    ForEach(review.singles) { group in
                        Button { selected = group } label: { UncategorizedGroupRow(group: group) }
                    }
                } header: {
                    Text("Без названия мерчанта")
                } footer: {
                    Text("Платежи из приложения банка, ЕРИП и переводы: по выписке не видно, за что они, поэтому они разбираются по одной.")
                }
            }
        }
        .buttonStyle(.plain)
        .overlay {
            if review.groups.isEmpty {
                ContentUnavailableView(
                    "Всё разложено",
                    systemImage: "checkmark.circle",
                    description: Text("Операций без категории нет")
                )
            }
        }
        .navigationTitle("Без категории")
        .sheet(item: $selected) { group in
            AssignCategorySheet(group: group, categories: model.pickerCategories(isExpense: group.isExpense)) { categoryID, always in
                Task { await review.assign(group, to: categoryID, always: always) }
            }
        }
        .errorAlert(Binding(get: { review.errorMessage }, set: { review.errorMessage = $0 }))
    }
}

private struct UncategorizedGroupRow: View {
    let group: UncategorizedReview.Group

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(group.title)
                    .lineLimit(2)
                Group {
                    if group.transactions.count == 1, let transaction = group.transactions.first {
                        Text(transaction.bookedAt, format: .dateTime.day().month().year())
                    } else {
                        Text("Операций: \(group.transactions.count)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                ForEach(group.totals, id: \.currency) { total in
                    MoneyText(total)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

/// Выбор категории для группы. Касание категории сразу применяет её и закрывает лист.
private struct AssignCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    let group: UncategorizedReview.Group
    let categories: [(category: FinanceCategory, depth: Int)]
    let onAssign: (FinanceCategory.ID, Bool) -> Void
    @State private var always = true

    private let preview = 3

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(group.transactions.prefix(preview)) { transaction in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(transaction.merchantRaw)
                                    .font(.subheadline)
                                    .lineLimit(3)
                                Text(transaction.bookedAt, format: .dateTime.day().month().year())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            MoneyText(transaction.amount)
                        }
                    }
                    if group.transactions.count > preview {
                        Text("Ещё операций: \(group.transactions.count - preview)")
                            .foregroundStyle(.secondary)
                    }
                }
                if group.canCreateRule {
                    Section {
                        Toggle("Всегда так для «\(group.title)»", isOn: $always)
                    } footer: {
                        if always {
                            Text("Следующие операции этого мерчанта получат категорию сами.")
                        } else {
                            Text("Категория достанется только этим операциям.")
                        }
                    }
                }
                Section("Категория") {
                    ForEach(categories, id: \.category.id) { item in
                        Button {
                            onAssign(item.category.id, always && group.canCreateRule)
                            dismiss()
                        } label: {
                            CategoryPickerLabel(category: item.category, depth: item.depth)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle(group.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }
}
