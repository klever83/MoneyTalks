import DesignSystem
import Domain
import StatementImport
import SwiftUI
import UniformTypeIdentifiers

/// Вкладка импорта: выбор файла выписки, превью и сохранение.
public struct ImportScreen: View {
    @State private var model: ImportModel
    @State private var isPickingFile = false
    private let banks: [BankInfo]

    public init(
        registry: ParserRegistry,
        banks: [BankInfo],
        accounts: any AccountRepository,
        transactions: any TransactionRepository,
        imports: any ImportRepository,
        categorizer: any TransactionCategorizer
    ) {
        self.banks = banks
        _model = State(initialValue: ImportModel(
            registry: registry,
            accounts: accounts,
            transactions: transactions,
            imports: imports,
            categorizer: categorizer
        ))
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Импорт")
                .toolbar { toolbar }
                .fileImporter(
                    isPresented: $isPickingFile,
                    allowedContentTypes: [.pdf, .commaSeparatedText, .plainText]
                ) { result in
                    if case let .success(url) = result {
                        Task { await model.open(url) }
                    }
                }
        }
        .errorAlert($model.errorMessage)
        .task { await model.observeAccounts() }
        .task { await model.observeBatches() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            SupportedBanksView(model: model, banks: banks) { isPickingFile = true }
        case .working:
            ProgressView("Читаю выписку…")
        case .choosingBank:
            List {
                Section {
                    ForEach(model.bankOptions) { option in
                        Button(option.name) {
                            Task { await model.choose(option) }
                        }
                    }
                } header: {
                    Text("Какого банка эта выписка?")
                } footer: {
                    Text("Банк не определился автоматически по содержимому файла.")
                }
            }
        case .preview:
            if let plan = model.plan {
                ImportPreviewView(model: model, plan: plan, fileName: model.fileName)
            }
        case let .done(imported):
            ContentUnavailableView {
                Label("Импорт завершён", systemImage: "checkmark.circle")
            } description: {
                Text("Добавлено операций: \(imported)")
            } actions: {
                Button("Импортировать ещё") { model.reset() }
            }
        case let .failed(message):
            ContentUnavailableView {
                Label("Не получилось", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Выбрать другой файл") { isPickingFile = true }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        switch model.phase {
        case .preview:
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { model.reset() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Импортировать") {
                    Task { await model.confirm() }
                }
                .disabled(model.isPlanning || (model.plan?.newTransactions.isEmpty ?? true))
            }
        case .choosingBank:
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { model.reset() }
            }
        default:
            ToolbarItem(placement: .primaryAction) {
                Button("Выбрать файл", systemImage: "doc.badge.plus") { isPickingFile = true }
                    .disabled(model.phase == .working)
            }
        }
    }
}

private struct SupportedBanksView: View {
    let model: ImportModel
    let banks: [BankInfo]
    let pickFile: () -> Void
    @State private var batchToRollback: ImportBatch?
    /// Счёт партии можно удалить вместе с откатом: проверяется при открытии диалога.
    @State private var canDeleteAccount = false

    var body: some View {
        List {
            Section {
                Button("Выбрать файл выписки", systemImage: "doc.badge.plus", action: pickFile)
            } footer: {
                Text("Выгрузите выписку в приложении или интернет-банке в PDF и выберите файл.")
            }
            if !model.batches.isEmpty {
                Section {
                    ForEach(model.batches) { batch in
                        BatchRow(batch: batch, accountName: model.accountName(for: batch))
                            .swipeActions {
                                Button("Отменить", systemImage: "arrow.uturn.backward", role: .destructive) {
                                    // Сначала проверка, потом диалог: открытый confirmationDialog не обязан
                                    // перерисовывать кнопки, а ответ для прошлой партии не попадёт в диалог новой.
                                    Task {
                                        canDeleteAccount = await model.canDeleteAccount(with: batch)
                                        batchToRollback = batch
                                    }
                                }
                            }
                    }
                } header: {
                    Text("История импорта")
                } footer: {
                    Text("Смахните, чтобы отменить импорт: его операции удалятся, и выписку можно будет загрузить заново.")
                }
            }
            Section("Поддерживаемые банки") {
                ForEach(banks, id: \.id) { bank in
                    Text(bank.name)
                }
            }
        }
        .confirmationDialog(
            "Отменить импорт?",
            isPresented: Binding(get: { batchToRollback != nil }, set: { if !$0 { batchToRollback = nil } }),
            titleVisibility: .visible,
            presenting: batchToRollback
        ) { batch in
            Button("Отменить импорт", role: .destructive) {
                Task { await model.rollback(batch) }
            }
            if canDeleteAccount {
                Button("Отменить и удалить счёт «\(model.accountName(for: batch))»", role: .destructive) {
                    Task { await model.rollback(batch, deleteAccount: true) }
                }
            }
        } message: { batch in
            Text("Операции из «\(batch.fileName)» (\(batch.transactionCount)) будут удалены. Переводы с операциями других выписок снимутся.")
        }
    }
}

/// Строка истории: счёт, файл, дата и число операций.
private struct BatchRow: View {
    let batch: ImportBatch
    let accountName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(accountName)
            Text(batch.fileName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(batch.importedAt, format: .dateTime.day().month().year().hour().minute())
                + Text(" · ")
                + Text("операций: \(batch.transactionCount)")
        }
        .font(.subheadline)
    }
}

/// Превью: счёт, итоги, предупреждения, найденные переводы и операции.
struct ImportPreviewView: View {
    let model: ImportModel
    let plan: ImportPlan
    let fileName: String

    var body: some View {
        List {
            Section {
                LabeledContent("Банк", value: plan.bank.name)
                LabeledContent("Файл", value: fileName)
                if let period = plan.statement.period {
                    LabeledContent("Период") {
                        Text(period.start, format: .dateTime.day().month().year())
                            + Text(" – ")
                            + Text(period.end, format: .dateTime.day().month().year())
                    }
                }
                if let opening = plan.statement.openingBalance, let closing = plan.statement.closingBalance {
                    LabeledContent("Остаток") {
                        Text(opening.formatted()) + Text(" → ") + Text(closing.formatted())
                    }
                }
                if let batch = model.alreadyImported {
                    Label {
                        Text("Этот файл уже импортирован \(batch.importedAt, format: .dateTime.day().month().year()). Повторные операции отсеются как дубли.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }
                if plan.updatesOpeningBalance {
                    Text("Выписка начинается раньше операций счёта: начальный остаток счёта возьмётся из неё.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if plan.mayMissPeriod {
                    Text("Между концом выписки и первой операцией счёта больше недели. Если за это время были операции, остаток сойдётся после импорта недостающего периода.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            Section("Счёт") {
                Picker("Счёт", selection: Binding(
                    get: { model.target },
                    set: { target in Task { await model.setTarget(target) } }
                )) {
                    if let proposed = model.proposedAccount {
                        Text("Новый: \(proposed.name)").tag(ImportModel.Target.new)
                    }
                    ForEach(model.targetAccounts) { account in
                        Text(account.name).tag(ImportModel.Target.existing(account.id))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("Итог") {
                LabeledContent("Новых операций", value: plan.newTransactions.count, format: .number)
                if plan.duplicates > 0 {
                    LabeledContent("Уже импортированы раньше", value: plan.duplicates, format: .number)
                }
                let transfers = plan.links.filter { $0.kind == .transfer && !$0.isExcluded }.count
                if transfers > 0 {
                    LabeledContent("Переводы между своими счетами", value: transfers, format: .number)
                }
                let cash = plan.links.filter { $0.kind == .cash && !$0.isExcluded }.count
                if cash > 0 {
                    LabeledContent("Снятие наличных", value: cash, format: .number)
                }
            }

            if !plan.statement.warnings.isEmpty {
                Section("Предупреждения") {
                    ForEach(plan.statement.warnings, id: \.self) { warning in
                        Label(warning.message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }

            if !plan.links.isEmpty {
                Section {
                    ForEach(plan.links) { link in
                        Toggle(isOn: Binding(
                            get: { !link.isExcluded },
                            set: { included in Task { await model.setIncluded(included, link: link) } }
                        )) {
                            LinkRow(link: link, accounts: model.accounts, newAccount: plan.account, newWallets: plan.newWallets)
                        }
                    }
                } header: {
                    Text("Переводы и наличные")
                } footer: {
                    Text("Не попадают в доходы и расходы. Снимите отметку, если это не перевод.")
                }
            }

            Section("Операции") {
                ForEach(plan.newTransactions) { transaction in
                    PreviewRow(transaction: transaction)
                }
            }
        }
    }
}

private struct LinkRow: View {
    let link: ImportLink
    let accounts: [Account]
    let newAccount: Account
    let newWallets: [Account]

    private func name(_ id: Account.ID) -> String {
        (accounts + [newAccount] + newWallets).first { $0.id == id }?.name ?? String(localized: "Наличные")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(link.kind == .cash ? "Снятие наличных" : "Перевод")
                .font(.subheadline.weight(.semibold))
            Text("\(name(link.outgoing.accountID)) → \(name(link.incoming.accountID))")
                .font(.caption)
            HStack {
                Text(link.outgoing.bookedAt, format: .dateTime.day().month())
                MoneyText(link.outgoing.amount.absolute)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct PreviewRow: View {
    let transaction: FinanceTransaction

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.merchantRaw)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(transaction.bookedAt, format: .dateTime.day().month())
                    if transaction.kind == .transfer {
                        Text("перевод")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            MoneyText(transaction.amount)
        }
    }
}
