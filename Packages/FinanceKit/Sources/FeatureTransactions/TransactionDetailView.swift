import DesignSystem
import Domain
import SwiftUI

/// Предложение «всегда так» после ручной смены категории.
struct AlwaysOffer: Identifiable {
    var id: CategoryRule.ID { rule.id }
    let rule: CategoryRule
    /// Мерчант для показа: `Evroopt`.
    let merchant: String
    let category: FinanceCategory?
    /// Прошлые операции мерчанта, которым правило поменяет категорию.
    let past: [FinanceTransaction]
}

/// Карточка операции: просмотр, правка суммы, даты, названия, категории и заметки, удаление.
struct TransactionDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let model: TransactionsViewModel
    let transactionID: FinanceTransaction.ID

    @State private var draft: Draft?
    @State private var offer: AlwaysOffer?
    @State private var isConfirmingDelete = false
    @State private var isSaving = false

    /// Редактируемые поля. Сумма — строка без знака, знак задаёт `isExpense`.
    struct Draft: Equatable {
        var amountText: String
        var isExpense: Bool
        var title: String
        var categoryID: FinanceCategory.ID?
        var date: Date
        var note: String

        init(_ transaction: FinanceTransaction) {
            amountText = AmountInput.text(for: transaction.amount.decimalValue)
            isExpense = transaction.amount.isNegative
            title = transaction.merchantNormalized
            categoryID = transaction.categoryID
            date = transaction.bookedAt
            note = transaction.note
        }

        /// Операция с правками или `nil`, если сумма не разбирается или название пустое.
        func applied(to transaction: FinanceTransaction) -> FinanceTransaction? {
            guard let value = AmountInput.parse(amountText), value != 0 else { return nil }
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            var result = transaction
            let magnitude = Money(value, currency: transaction.amount.currency)
            result.amount = isExpense ? magnitude.negated : magnitude
            result.merchantNormalized = trimmed
            result.categoryID = categoryID
            result.bookedAt = date
            result.note = note
            return result
        }
    }

    var body: some View {
        Group {
            if let transaction = model.transaction(id: transactionID) {
                form(for: transaction)
            } else {
                ContentUnavailableView("Операция удалена", systemImage: "trash")
            }
        }
        .navigationTitle("Операция")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private func form(for transaction: FinanceTransaction) -> some View {
        let binding = Binding<Draft>(
            get: { draft ?? Draft(transaction) },
            set: { draft = $0 }
        )
        let edited = binding.wrappedValue.applied(to: transaction)
        let isTransfer = transaction.kind == .transfer

        Form {
            Section {
                if isTransfer {
                    LabeledContent("Сумма") { MoneyText(transaction.amount) }
                } else {
                    Picker("Тип", selection: binding.isExpense) {
                        Text("Расход").tag(true)
                        Text("Доход").tag(false)
                    }
                    .pickerStyle(.segmented)
                    LabeledContent("Сумма") {
                        TextField("0", text: binding.amountText)
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Text(transaction.amount.currency.code)
                            .foregroundStyle(.secondary)
                    }
                }
                if let original = transaction.originalAmount {
                    LabeledContent("В валюте покупки") { MoneyText(original) }
                }
            } footer: {
                if transaction.isStaleHold() {
                    Text("Операция в обработке больше месяца: скорее всего, банк её отменил или провёл с другой суммой. Если проведённая версия уже есть в списке, удалите эту, иначе остаток будет неверным.")
                } else if transaction.isPending {
                    Text("Операция в обработке у банка. Когда она проведётся, следующая выписка заменит её проведённой.")
                }
            }

            Section {
                TextField("Название", text: binding.title)
                if isTransfer {
                    LabeledContent("Категория", value: String(localized: "Перевод между счетами"))
                } else {
                    Picker("Категория", selection: binding.categoryID) {
                        Text("Без категории").tag(FinanceCategory.ID?.none)
                        ForEach(categories(isExpense: binding.wrappedValue.isExpense, current: transaction.categoryID), id: \.category.id) { item in
                            CategoryPickerLabel(category: item.category, depth: item.depth).tag(Optional(item.category.id))
                        }
                    }
                }
                DatePicker("Дата", selection: binding.date)
                TextField("Заметка", text: binding.note, axis: .vertical)
            }

            Section {
                if let account = model.account(for: transaction) {
                    LabeledContent("Счёт", value: account.name)
                }
                if transaction.source == .imported, transaction.merchantRaw != binding.wrappedValue.title {
                    LabeledContent("В выписке", value: transaction.merchantRaw)
                }
                if let mcc = transaction.mcc {
                    LabeledContent("MCC", value: String(mcc))
                }
            }

            Section {
                Button("Удалить операцию", role: .destructive) { isConfirmingDelete = true }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") {
                    guard let edited else { return }
                    isSaving = true
                    Task {
                        let result = await model.save(edited, original: transaction)
                        isSaving = false
                        draft = nil
                        if let result { offer = result } else { dismiss() }
                    }
                }
                .disabled(edited == nil || edited == transaction || isSaving)
            }
        }
        .confirmationDialog(
            "Удалить операцию?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                Task {
                    await model.delete(transaction)
                    dismiss()
                }
            }
        }
        .confirmationDialog(
            alwaysTitle,
            isPresented: Binding(get: { offer != nil }, set: { if !$0 { offer = nil; dismiss() } }),
            titleVisibility: .visible,
            presenting: offer
        ) { offer in
            if !offer.past.isEmpty {
                Button("Всегда, и для прошлых (\(offer.past.count))") { accept(offer, applyToPast: true) }
            }
            Button(offer.past.isEmpty ? "Всегда так" : "Всегда, только для новых") { accept(offer, applyToPast: false) }
            Button("Только эту операцию", role: .cancel) {}
        }
    }

    private var alwaysTitle: String {
        guard let offer else { return "" }
        let category = offer.category?.displayName ?? String(localized: "Без категории")
        return String(localized: "Всегда относить «\(offer.merchant)» к «\(category)»?")
    }

    /// Диалог закрывается сам и закрывает карточку (см. `isPresented`), а сохранение правила
    /// доводит view model, которая живёт дольше карточки.
    private func accept(_ offer: AlwaysOffer, applyToPast: Bool) {
        Task { await model.acceptAlways(offer, applyToPast: applyToPast) }
    }

    /// Видимые категории нужного типа деревом; текущая категория операции остаётся в списке,
    /// даже если она скрыта или другого типа.
    private func categories(isExpense: Bool, current: FinanceCategory.ID?) -> [(category: FinanceCategory, depth: Int)] {
        let kind: FinanceCategory.Kind = isExpense ? .expense : .income
        let hidden = FinanceCategory.hiddenIDs(model.categories)
        return FinanceCategory.tree(model.categories.filter { ($0.kind == kind && !hidden.contains($0.id)) || $0.id == current })
    }
}

extension CategoryRule.Condition {
    /// Ключ мерчанта для показа в предложении «всегда так»: `yandex go` → `Yandex Go`.
    var merchantKeyTitle: String? {
        guard case let .merchantKey(key) = self else { return nil }
        return key.capitalized(with: Locale(identifier: "ru_BY"))
    }
}
