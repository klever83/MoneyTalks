import DesignSystem
import Domain
import SwiftUI

@MainActor
@Observable
final class TransactionsViewModel {
    private(set) var transactions: [FinanceTransaction] = []
    private(set) var accounts: [Account] = []
    private(set) var categories: [FinanceCategory] = []
    var errorMessage: String?

    private let transactionRepository: any TransactionRepository
    private let accountRepository: any AccountRepository
    private let categoryRepository: any CategoryRepository
    private let categorizer: any TransactionCategorizer

    init(
        transactions: any TransactionRepository,
        accounts: any AccountRepository,
        categories: any CategoryRepository,
        categorizer: any TransactionCategorizer
    ) {
        transactionRepository = transactions
        accountRepository = accounts
        categoryRepository = categories
        self.categorizer = categorizer
    }

    /// Операции, сгруппированные по дню, новые сверху.
    var days: [(day: Date, items: [FinanceTransaction])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: transactions) { calendar.startOfDay(for: $0.bookedAt) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    func category(for transaction: FinanceTransaction) -> FinanceCategory? {
        categories.first { $0.id == transaction.categoryID }
    }

    func observe() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.observeTransactions() }
            group.addTask { await self.observeAccounts() }
            group.addTask { await self.observeCategories() }
        }
    }

    private func observeTransactions() async {
        do {
            for try await items in transactionRepository.observeTransactions(TransactionQuery(limit: 500)) {
                transactions = items
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func observeAccounts() async {
        do {
            for try await items in accountRepository.observeAccounts() {
                accounts = items
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func observeCategories() async {
        do {
            for try await items in categoryRepository.observeCategories() {
                categories = items
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addManual(_ draft: ManualTransactionDraft) async {
        guard let account = accounts.first(where: { $0.id == draft.accountID }), let value = draft.amount else { return }
        let magnitude = Money(value < 0 ? -value : value, currency: account.currency)
        let amount = draft.isExpense ? magnitude.negated : magnitude
        let transaction = FinanceTransaction(
            accountID: account.id,
            bookedAt: draft.date,
            amount: amount,
            merchantRaw: draft.title,
            categoryID: draft.categoryID,
            categoryLocked: draft.categoryID != nil,
            note: draft.note,
            source: .manual
        )
        do {
            // Категорию, выбранную вручную, правила не трогают; без неё — подсказка по описанию.
            try await transactionRepository.save(try await categorizer.categorize([transaction]))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ transaction: FinanceTransaction) async {
        do {
            try await transactionRepository.delete(transaction.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

public struct TransactionsScreen: View {
    @State private var model: TransactionsViewModel
    @State private var isAdding = false

    public init(
        transactions: any TransactionRepository,
        accounts: any AccountRepository,
        categories: any CategoryRepository,
        categorizer: any TransactionCategorizer
    ) {
        _model = State(initialValue: TransactionsViewModel(
            transactions: transactions,
            accounts: accounts,
            categories: categories,
            categorizer: categorizer
        ))
    }

    public var body: some View {
        NavigationStack {
            List {
                ForEach(model.days, id: \.day) { day in
                    Section {
                        ForEach(day.items) { transaction in
                            TransactionRow(transaction: transaction, category: model.category(for: transaction))
                                .swipeActions {
                                    Button("Удалить", systemImage: "trash", role: .destructive) {
                                        Task { await model.delete(transaction) }
                                    }
                                }
                        }
                    } header: {
                        Text(day.day, format: .dateTime.day().month(.wide).weekday(.wide))
                    }
                }
            }
            .overlay {
                if model.transactions.isEmpty {
                    ContentUnavailableView(
                        "Операций пока нет",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Импортируйте выписку или добавьте операцию вручную")
                    )
                }
            }
            .navigationTitle("Операции")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Добавить", systemImage: "plus") { isAdding = true }
                        .disabled(model.accounts.isEmpty)
                }
            }
            .sheet(isPresented: $isAdding) {
                AddTransactionForm(accounts: model.accounts, categories: model.categories) { draft in
                    Task { await model.addManual(draft) }
                }
            }
            .errorAlert($model.errorMessage)
            .task { await model.observe() }
        }
    }
}

private struct TransactionRow: View {
    let transaction: FinanceTransaction
    let category: FinanceCategory?

    var body: some View {
        HStack {
            Image(systemName: category?.systemImage ?? "questionmark.circle")
                .foregroundStyle(category?.color ?? .secondary)
                .frame(width: 28)
            VStack(alignment: .leading) {
                Text(transaction.merchantNormalized)
                Text(category?.displayName ?? String(localized: "Без категории"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            MoneyText(transaction.amount)
        }
    }
}
