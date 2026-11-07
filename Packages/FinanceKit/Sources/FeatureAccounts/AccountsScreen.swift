import DesignSystem
import Domain
import SwiftUI

@MainActor
@Observable
final class AccountsViewModel {
    private(set) var accounts: [Account] = []
    var errorMessage: String?

    private let repository: any AccountRepository

    init(repository: any AccountRepository) {
        self.repository = repository
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

    func add(name: String, kind: Account.Kind, currency: Currency) async {
        do {
            try await repository.save(Account(name: name, kind: kind, currency: currency))
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
}

public struct AccountsScreen: View {
    @State private var model: AccountsViewModel
    @State private var isAdding = false
    @State private var accountToDelete: Account?

    public init(repository: any AccountRepository) {
        _model = State(initialValue: AccountsViewModel(repository: repository))
    }

    public var body: some View {
        NavigationStack {
            List {
                ForEach(model.accounts) { account in
                    AccountRow(account: account)
                        .swipeActions {
                            Button("Удалить", systemImage: "trash", role: .destructive) {
                                accountToDelete = account
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
                AddAccountForm { name, kind, currency in
                    Task { await model.add(name: name, kind: kind, currency: currency) }
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
        }
    }
}

private struct AccountRow: View {
    let account: Account

    var body: some View {
        Label {
            VStack(alignment: .leading) {
                Text(account.name)
                Text(account.kind.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(account.currency.code)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: account.kind.systemImage)
        }
    }
}

private struct AddAccountForm: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: Account.Kind = .card
    @State private var currency: Currency = .byn

    let onSave: (String, Account.Kind, Currency) -> Void

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
            }
            .navigationTitle("Новый счёт")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        onSave(name.trimmingCharacters(in: .whitespaces), kind, currency)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
