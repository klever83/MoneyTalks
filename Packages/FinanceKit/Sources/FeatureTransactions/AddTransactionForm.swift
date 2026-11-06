import DesignSystem
import Domain
import SwiftUI

struct ManualTransactionDraft: Sendable {
    var accountID: Account.ID
    var isExpense: Bool
    var amount: Decimal?
    var title: String
    var categoryID: FinanceCategory.ID?
    var date: Date
    var note: String
}

/// Ручной ввод операции: в первую очередь для наличных.
struct AddTransactionForm: View {
    @Environment(\.dismiss) private var dismiss

    let accounts: [Account]
    let categories: [FinanceCategory]
    let onSave: (ManualTransactionDraft) -> Void

    @State private var accountID: Account.ID?
    @State private var isExpense = true
    @State private var amount: Decimal?
    @State private var title = ""
    @State private var categoryID: FinanceCategory.ID?
    @State private var date = Date.now
    @State private var note = ""

    private var availableCategories: [FinanceCategory] {
        categories.filter { $0.kind == (isExpense ? .expense : .income) }
    }

    private var canSave: Bool {
        accountID != nil && (amount ?? 0) != 0 && !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Тип", selection: $isExpense) {
                    Text("Расход").tag(true)
                    Text("Доход").tag(false)
                }
                .pickerStyle(.segmented)

                TextField("Сумма", value: $amount, format: .number)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif

                TextField("Описание", text: $title)

                Picker("Счёт", selection: $accountID) {
                    ForEach(accounts) { account in
                        Text("\(account.name) · \(account.currency.code)").tag(Optional(account.id))
                    }
                }

                Picker("Категория", selection: $categoryID) {
                    Text("Без категории").tag(FinanceCategory.ID?.none)
                    ForEach(availableCategories) { category in
                        Label(category.displayName, systemImage: category.systemImage).tag(Optional(category.id))
                    }
                }

                DatePicker("Дата", selection: $date)
                TextField("Заметка", text: $note, axis: .vertical)
            }
            .navigationTitle("Новая операция")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        guard let accountID else { return }
                        onSave(ManualTransactionDraft(
                            accountID: accountID,
                            isExpense: isExpense,
                            amount: amount,
                            title: title.trimmingCharacters(in: .whitespaces),
                            categoryID: categoryID,
                            date: date,
                            note: note
                        ))
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                // По умолчанию — счёт наличных, если он есть.
                accountID = accountID ?? (accounts.first { $0.kind == .cash } ?? accounts.first)?.id
            }
            .onChange(of: isExpense) {
                categoryID = nil
            }
        }
    }
}
