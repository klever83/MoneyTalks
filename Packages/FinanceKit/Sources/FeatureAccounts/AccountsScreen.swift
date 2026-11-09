import DesignSystem
import Domain
import SwiftUI

@MainActor
@Observable
final class AccountsViewModel {
    private(set) var accounts: [Account] = []
    /// Текущие остатки: начальный остаток плюс операции. Обновляются после каждого импорта и правки.
    private(set) var balances: [Account.ID: Money] = [:]
    var errorMessage: String?

    private let repository: any AccountRepository

    init(repository: any AccountRepository) {
        self.repository = repository
    }

    /// Итоги по валютам в порядке первого появления валюты в списке счетов.
    var totals: [Money] {
        Self.totals(accounts.compactMap { balances[$0.id] })
    }

    func balance(of account: Account) -> Money? {
        balances[account.id]
    }

    func observe() async {
        do {
            for try await accounts in repository.observeAccounts() {
                self.accounts = accounts
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func observeBalances() async {
        do {
            for try await balances in repository.observeBalances() {
                self.balances = balances
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Новый счёт: введённый остаток становится начальным, операций у счёта ещё нет.
    func add(name: String, kind: Account.Kind, currency: Currency, balance: Decimal?) async {
        let opening = balance.map { Money($0, currency: currency) }
        await save(Account(name: name, kind: kind, currency: currency, openingBalance: opening))
    }

    /// Правка счёта. Новый текущий остаток меняет начальный, операции не трогаются.
    func update(_ account: Account, name: String, kind: Account.Kind, currentBalance: Decimal?) async {
        do {
            let updated = try Self.edited(
                account, name: name, kind: kind,
                currentBalance: currentBalance, knownBalance: balances[account.id]
            )
            await save(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ account: Account) async {
        do {
            try await repository.delete(account.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save(_ account: Account) async {
        do {
            try await repository.save(account)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static func totals(_ balances: [Money]) -> [Money] {
        var order: [Currency] = []
        var sums: [Currency: Int64] = [:]
        for balance in balances {
            if sums[balance.currency] == nil { order.append(balance.currency) }
            sums[balance.currency, default: 0] += balance.minorUnits
        }
        return order.map { Money(minorUnits: sums[$0] ?? 0, currency: $0) }
    }

    /// Счёт после правки. Без известного остатка (поток ещё не пришёл) начальный остаток не меняется.
    static func edited(
        _ account: Account, name: String, kind: Account.Kind,
        currentBalance: Decimal?, knownBalance: Money?
    ) throws(MoneyError) -> Account {
        var updated = account
        updated.name = name
        updated.kind = kind
        if let currentBalance, let knownBalance {
            let target = Money(currentBalance, currency: account.currency)
            if target != knownBalance {
                updated = try updated.withCurrentBalance(target, current: knownBalance)
            }
        }
        return updated
    }
}

public struct AccountsScreen: View {
    @State private var model: AccountsViewModel
    @State private var isAdding = false
    @State private var editing: Account?
    @State private var accountToDelete: Account?

    public init(repository: any AccountRepository) {
        _model = State(initialValue: AccountsViewModel(repository: repository))
    }

    public var body: some View {
        NavigationStack {
            List {
                if !model.totals.isEmpty {
                    Section("Итого") {
                        ForEach(model.totals, id: \.currency) { total in
                            LabeledContent(total.currency.code) {
                                BalanceText(balance: total)
                            }
                        }
                    }
                }
                Section {
                    ForEach(model.accounts) { account in
                        Button {
                            editing = account
                        } label: {
                            AccountRow(account: account, balance: model.balance(of: account))
                        }
                        .foregroundStyle(.primary)
                        .swipeActions {
                            Button("Удалить", systemImage: "trash", role: .destructive) {
                                accountToDelete = account
                            }
                        }
                    }
                }
            }
            .overlay {
                if model.accounts.isEmpty {
                    ContentUnavailableView(
                        "Нет счетов",
                        systemImage: "creditcard",
                        description: Text("Добавьте карту, счёт или наличные")
                    )
                }
            }
            .navigationTitle("Счета")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Добавить", systemImage: "plus") { isAdding = true }
                }
            }
            .sheet(isPresented: $isAdding) {
                AddAccountForm { name, kind, currency, balance in
                    Task { await model.add(name: name, kind: kind, currency: currency, balance: balance) }
                }
            }
            .sheet(item: $editing) { account in
                EditAccountForm(account: account, balance: model.balance(of: account)) { name, kind, balance in
                    Task { await model.update(account, name: name, kind: kind, currentBalance: balance) }
                }
            }
            .confirmationDialog(
                "Удалить счёт?",
                isPresented: Binding(
                    get: { accountToDelete != nil },
                    set: { if !$0 { accountToDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: accountToDelete
            ) { account in
                Button("Удалить счёт", role: .destructive) {
                    Task { await model.delete(account) }
                }
            } message: { account in
                Text("Счёт «\(account.name)» и все его операции будут удалены.")
            }
            .errorAlert($model.errorMessage)
            .task { await model.observe() }
            .task { await model.observeBalances() }
        }
    }
}

/// Остаток без «доходного» цвета: положительный остаток — не доход. Отрицательный выделяется.
private struct BalanceText: View {
    let balance: Money

    var body: some View {
        Text(balance.formatted())
            .monospacedDigit()
            .foregroundStyle(balance.isNegative ? Color.red : Color.primary)
    }
}

private struct AccountRow: View {
    let account: Account
    let balance: Money?

    var body: some View {
        Label {
            HStack {
                VStack(alignment: .leading) {
                    Text(account.name)
                    Text(account.kind.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let balance {
                    BalanceText(balance: balance)
                } else {
                    Text(account.currency.code)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: account.kind.systemImage)
        }
    }
}

/// Поле остатка: минус разрешён (кредитная карта), пустое поле — остаток не задан.
private struct BalanceField: View {
    let title: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        TextField(title, text: $text)
            .monospacedDigit()
            #if os(iOS)
            // На `.decimalPad` нет минуса, а остаток кредитки отрицательный.
            .keyboardType(.numbersAndPunctuation)
            #endif
    }
}

private struct AddAccountForm: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: Account.Kind = .card
    @State private var currency: Currency = .byn
    @State private var balanceText = ""

    let onSave: (String, Account.Kind, Currency, Decimal?) -> Void

    private var balance: Decimal? {
        AmountInput.parse(balanceText, allowsNegative: true)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (balanceText.isEmpty || balance != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Название", text: $name)
                Picker("Тип", selection: $kind) {
                    ForEach(Account.Kind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                Picker("Валюта", selection: $currency) {
                    ForEach(Currency.supported) { currency in
                        Text(currency.code).tag(currency)
                    }
                }
                Section {
                    BalanceField(title: "Остаток", text: $balanceText)
                } footer: {
                    Text("Сколько сейчас на счёте. Можно оставить пустым и задать позже.")
                }
            }
            .navigationTitle("Новый счёт")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        onSave(name.trimmingCharacters(in: .whitespaces), kind, currency, balance)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

private struct EditAccountForm: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var kind: Account.Kind
    @State private var balanceText: String
    private let currency: Currency

    let onSave: (String, Account.Kind, Decimal?) -> Void

    init(account: Account, balance: Money?, onSave: @escaping (String, Account.Kind, Decimal?) -> Void) {
        _name = State(initialValue: account.name)
        _kind = State(initialValue: account.kind)
        _balanceText = State(initialValue: balance.map { AmountInput.signedText(for: $0.decimalValue) } ?? "")
        currency = account.currency
        self.onSave = onSave
    }

    private var balance: Decimal? {
        AmountInput.parse(balanceText, allowsNegative: true)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (balanceText.isEmpty || balance != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Название", text: $name)
                Picker("Тип", selection: $kind) {
                    ForEach(Account.Kind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                LabeledContent("Валюта", value: currency.code)
                Section {
                    BalanceField(title: "Текущий остаток", text: $balanceText)
                } footer: {
                    Text("Остаток считается по операциям. Если он разошёлся с банком, введите остаток из приложения банка: операции не изменятся.")
                }
            }
            .navigationTitle("Счёт")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        onSave(name.trimmingCharacters(in: .whitespaces), kind, balance)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
