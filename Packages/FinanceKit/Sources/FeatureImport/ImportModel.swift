import CryptoKit
import Domain
import Foundation
import StatementImport

/// Импорт выписки: файл → банк → превью → сохранение.
@MainActor
@Observable
final class ImportModel {
    enum Phase: Equatable {
        case idle
        case working
        case choosingBank
        case preview
        case done(imported: Int)
        case failed(String)
    }

    /// Счёт, в который идёт выписка.
    enum Target: Hashable {
        case new
        case existing(Account.ID)
    }

    struct BankOption: Identifiable {
        var id: String { parser.id.rawValue }
        var name: String { parser.bank.name }
        let parser: any StatementParser
    }

    private(set) var phase: Phase = .idle
    private(set) var accounts: [Account] = []
    private(set) var bankOptions: [BankOption] = []
    private(set) var plan: ImportPlan?
    private(set) var proposedAccount: Account?
    private(set) var fileName = ""
    private(set) var target: Target = .new
    /// Идёт пересчёт превью: подтверждать нельзя, план ещё старый.
    private(set) var isPlanning = false
    /// Прошлые импорты, новые сверху: их можно откатить.
    private(set) var batches: [ImportBatch] = []
    /// Этот же файл уже импортирован: превью предупреждает.
    private(set) var alreadyImported: ImportBatch?
    var errorMessage: String?
    private var fileHash: String?
    private var generation = 0
    private var document: StatementDocument?
    private var statement: ParsedStatement?
    private var bank: BankInfo?
    private var excluded: Set<UUID> = []
    private var batchID = UUID()

    private let registry: ParserRegistry
    private let accountRepository: any AccountRepository
    private let transactionRepository: any TransactionRepository
    private let importRepository: any ImportRepository
    private let categorizer: any TransactionCategorizer

    init(
        registry: ParserRegistry,
        accounts: any AccountRepository,
        transactions: any TransactionRepository,
        imports: any ImportRepository,
        categorizer: any TransactionCategorizer
    ) {
        self.registry = registry
        accountRepository = accounts
        transactionRepository = transactions
        importRepository = imports
        self.categorizer = categorizer
    }

    /// Счета, в которые можно положить выписку: той же валюты, кроме наличных.
    var targetAccounts: [Account] {
        guard let currency = proposedAccount?.currency else { return [] }
        return accounts.filter { $0.kind != .cash && $0.currency == currency }
    }

    func observeBatches() async {
        do {
            for try await items in importRepository.observeBatches() {
                batches = items
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Откат импорта целиком (см. `ImportRepository.rollback`). Операциям других выписок, с которых
    /// снят перевод, категория проставляется заново по правилам: при связи она была стёрта.
    /// - Parameter deleteAccount: удалить и счёт, созданный этим импортом.
    func rollback(_ batch: ImportBatch, deleteAccount: Bool = false) async {
        do {
            let released = try await importRepository.rollback(batch.id)
            let categorized = try await categorizer.categorize(released)
            let changed = zip(released, categorized).filter { $0.categoryID != $1.categoryID }.map(\.1)
            if !changed.isEmpty {
                try await transactionRepository.save(changed)
            }
            if deleteAccount {
                try await accountRepository.delete(batch.accountID)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Счёт можно удалить вместе с откатом, только если его создал этот импорт и других импортов
    /// в него нет: иначе удалились бы и их операции.
    func canDeleteAccount(with batch: ImportBatch) -> Bool {
        batch.createdAccount && !batches.contains { $0.id != batch.id && $0.accountID == batch.accountID }
    }

    func accountName(for batch: ImportBatch) -> String {
        accounts.first { $0.id == batch.accountID }?.name ?? batch.bankName
    }

    func observeAccounts() async {
        do {
            for try await items in accountRepository.observeAccounts() {
                accounts = items
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Шаги

    func open(_ url: URL) async {
        reset()
        phase = .working
        fileName = url.lastPathComponent
        do {
            let name = fileName
            let (document, hash) = try await Task.detached(priority: .userInitiated) {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                return (try Self.readDocument(data, fileName: name), Self.fileHash(data))
            }.value
            self.document = document
            fileHash = hash
            // Предупреждение, а не запрет: повторные строки всё равно отсеет дедупликация.
            alreadyImported = try? await importRepository.batch(fileHash: hash)
            if let parser = registry.bestMatch(for: document) {
                await parse(with: parser)
            } else {
                bankOptions = registry.parsers
                    .filter { $0.formats.contains(document.format) }
                    .map(BankOption.init)
                phase = bankOptions.isEmpty
                    ? .failed(String(localized: "Банк этой выписки пока не поддерживается."))
                    : .choosingBank
            }
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    func choose(_ option: BankOption) async {
        phase = .working
        await parse(with: option.parser)
    }

    func setTarget(_ target: Target) async {
        guard target != self.target else { return }
        self.target = target
        await replan()
    }

    func setIncluded(_ included: Bool, link: ImportLink) async {
        if included { excluded.remove(link.id) } else { excluded.insert(link.id) }
        await replan()
    }

    func confirm() async {
        guard let plan, !isPlanning else { return }
        phase = .working
        let rows = plan.statement.rows.map(\.bookedAt)
        let batch = ImportBatch(
            id: plan.batchID,
            accountID: plan.account.id,
            bankName: plan.bank.name,
            fileName: fileName,
            fileHash: fileHash,
            period: plan.statement.period ?? rows.min().flatMap { first in rows.max().map { DateInterval(start: first, end: $0) } },
            transactionCount: plan.newTransactions.count,
            duplicateCount: plan.duplicates,
            previousOpeningBalanceMinor: plan.previousOpeningBalance?.minorUnits,
            appliedOpeningBalanceMinor: plan.updatesOpeningBalance ? plan.account.openingBalance.minorUnits : nil,
            createdAccount: plan.isNewAccount
        )
        do {
            try await importRepository.commitImport(
                batch: batch,
                accounts: plan.accountsToSave,
                transactions: plan.transactionsToSave,
                links: plan.transferLinks
            )
            phase = .done(imported: plan.newTransactions.count)
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    func reset() {
        phase = .idle
        document = nil
        statement = nil
        bank = nil
        plan = nil
        proposedAccount = nil
        bankOptions = []
        excluded = []
        target = .new
        fileHash = nil
        alreadyImported = nil
        batchID = UUID()
        generation += 1
        isPlanning = false
    }

    // MARK: - Внутреннее

    private func parse(with parser: any StatementParser) async {
        guard let document else { return }
        do {
            let statement = try await Task.detached(priority: .userInitiated) {
                try parser.parse(document)
            }.value
            guard !statement.rows.isEmpty else {
                phase = .failed(String(localized: "В выписке нет операций."))
                return
            }
            self.statement = statement
            bank = parser.bank
            let proposed = ImportPlanner.proposedAccount(for: statement, bank: parser.bank)
            proposedAccount = proposed
            target = ImportPlanner.matchAccount(for: statement.accountHint, bank: parser.bank, among: accounts)
                .map { .existing($0.id) } ?? .new
            await replan()
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    /// Пересчёт превью. Если за время запросов к базе пользователь снова что-то переключил,
    /// результат устарел и отбрасывается: применяется только последний пересчёт.
    private func replan() async {
        guard let statement, let bank, let proposedAccount else { return }
        generation += 1
        let current = generation
        isPlanning = true
        defer { if current == generation { isPlanning = false } }
        let account: Account
        let isNew: Bool
        switch target {
        case .new:
            account = proposedAccount
            isNew = true
        case let .existing(id):
            guard let existing = accounts.first(where: { $0.id == id }) else { return }
            account = existing
            isNew = false
        }
        do {
            let fingerprints = isNew ? [] : try await transactionRepository.fingerprints(accountID: account.id)
            let earliest = isNew ? nil : try await transactionRepository.earliestBookedAt(accountID: account.id)
            let dates = statement.rows.map(\.bookedAt)
            let window = TransferMatcher.defaultWindow
            let deletedAccounts = try await accountRepository.deletedAccountIDs()
            var recent: [FinanceTransaction] = []
            if let first = dates.min(), let last = dates.max() {
                let interval = DateInterval(start: first.addingTimeInterval(-window), end: last.addingTimeInterval(window + 1))
                recent = try await transactionRepository.transactions(TransactionQuery(interval: interval))
            }
            var plan = ImportPlanner.plan(
                statement: statement,
                bank: bank,
                account: account,
                isNewAccount: isNew,
                existingFingerprints: fingerprints,
                existingAccounts: accounts,
                earliestTransactionDate: earliest,
                deletedAccountIDs: deletedAccounts,
                recentTransactions: recent,
                walletName: String(localized: "Наличные"),
                excludedLinks: excluded,
                batchID: batchID
            )
            // Категории по правилам. Переводы не категоризуются; снятая в превью связь
            // снова делает операции расходом и доходом, и они получают категорию при пересчёте.
            plan.newTransactions = try await categorizer.categorize(plan.newTransactions)
            plan.walletTransactions = try await categorizer.categorize(plan.walletTransactions)
            guard current == generation else { return }
            self.plan = plan
            phase = .preview
        } catch {
            guard current == generation else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    /// SHA-256 файла в hex: по нему распознаётся повторная загрузка того же файла.
    nonisolated static func fileHash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func readDocument(_ data: Data, fileName: String) throws -> StatementDocument {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "pdf":
            return try PDFStatementReader.document(from: data, fileName: fileName)
        case "csv", "txt":
            guard let text = CSVReader.decode(data) else { throw ImportFileError.unreadable }
            return StatementDocument(fileName: fileName, format: .csv, content: .table(CSVReader.parse(text)))
        default:
            throw ImportFileError.unsupported
        }
    }

    static func message(for error: any Error) -> String {
        switch error {
        case let failure as PDFStatementReader.Failure:
            switch failure {
            case .unreadable: String(localized: "Не удалось открыть PDF.")
            case .locked: String(localized: "PDF защищён паролем. Выгрузите выписку без пароля.")
            case .noText: String(localized: "В PDF нет текста: похоже, это скан. Нужна выписка из приложения банка.")
            case .rotatedPage: String(localized: "В PDF есть повёрнутые страницы, такую выписку прочитать не получится.")
            }
        case let failure as ParseError:
            switch failure {
            case .unsupportedFormat: String(localized: "Формат файла не подходит для этого банка.")
            case let .missingColumn(name): String(localized: "Не удалось разобрать выписку: не найдено «\(name)».")
            case let .invalidValue(line, field, value):
                String(localized: "Не удалось разобрать выписку: строка \(line), \(field) «\(value)».")
            }
        case ImportFileError.unsupported:
            String(localized: "Поддерживаются выписки в PDF и CSV.")
        case ImportFileError.unreadable:
            String(localized: "Не удалось прочитать файл.")
        case ImportCommitError.transactionChanged:
            String(localized: "Операции изменились, пока шёл импорт. Выберите файл ещё раз.")
        default:
            error.localizedDescription
        }
    }
}

enum ImportFileError: Error {
    case unsupported
    case unreadable
}
