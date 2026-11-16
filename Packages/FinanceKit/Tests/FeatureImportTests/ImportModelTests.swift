import Categorization
import Domain
@testable import FeatureImport
import Foundation
import Persistence
import StatementImport
import Testing

/// Парсер-заглушка: содержимое файла не читает и отдаёт заданные строки.
struct FakeParser: StatementParser {
    var id: ParserID = "test.bank"
    var bank = BankInfo(id: "test.bank", name: "Тестбанк", country: "BY")
    var formats: Set<StatementFormat> = [.csv]
    var score = 1.0
    var rows: [ParsedRow]

    func confidence(for document: StatementDocument) -> Double { score }

    func parse(_ document: StatementDocument) throws(ParseError) -> ParsedStatement {
        ParsedStatement(accountHint: AccountHint(maskedNumber: "1234", currency: .byn), rows: rows)
    }
}

@MainActor
@Suite("Импорт: view model")
struct ImportModelTests {
    let database: AppDatabase
    let accounts: GRDBAccountRepository
    let transactions: GRDBTransactionRepository
    let folder: URL
    static let day = Date(timeIntervalSince1970: 1_790_000_000)
    static let rows = [
        ParsedRow(bookedAt: day, amount: Money(minorUnits: -1_250, currency: .byn), description: "EVROOPT MINSK"),
        ParsedRow(bookedAt: day.addingTimeInterval(3_600), amount: Money(minorUnits: -300, currency: .byn), description: "KOFEYNYA"),
    ]

    init() throws {
        database = try AppDatabase.inMemory()
        accounts = GRDBAccountRepository(database: database)
        transactions = GRDBTransactionRepository(database: database)
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("ImportModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func makeModel(_ parser: FakeParser = FakeParser(rows: rows)) -> ImportModel {
        ImportModel(
            registry: ParserRegistry(parsers: [parser]),
            accounts: accounts,
            transactions: transactions,
            imports: GRDBImportRepository(database: database),
            categorizer: RuleBasedTransactionCategorizer(repository: GRDBCategoryRuleRepository(database: database))
        )
    }

    func file(_ name: String = "statement.csv", _ text: String = "Дата;Сумма\n01.10.2026;-12,50\n") throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    /// Ждёт, пока поток `observe*` доставит нужное состояние.
    func waitUntil(_ condition: () -> Bool) async throws {
        var attempts = 0
        while !condition(), attempts < 500 {
            try await Task.sleep(for: .milliseconds(10))
            attempts += 1
        }
        #expect(condition())
    }

    @Test("Файл → превью → сохранение; тот же файл повторно: предупреждение и только дубли")
    func importAndReimport() async throws {
        let model = makeModel()
        let observing = Task { await model.observeAccounts() }
        let observingBatches = Task { await model.observeBatches() }
        defer { observing.cancel(); observingBatches.cancel() }
        let url = try file()

        await model.open(url)
        #expect(model.phase == .preview)
        #expect(model.target == .new)
        #expect(model.alreadyImported == nil)
        #expect(model.plan?.newTransactions.count == 2)

        await model.confirm()
        #expect(model.phase == .done(imported: 2))
        try await waitUntil { model.batches.count == 1 && model.accounts.count == 1 }
        #expect(try await transactions.transactions(TransactionQuery()).count == 2)

        await model.open(url)
        #expect(model.phase == .preview)
        #expect(model.alreadyImported?.id == model.batches.first?.id)
        #expect(model.target == .existing(try #require(model.accounts.first).id))
        #expect(model.plan?.newTransactions.isEmpty == true)
        #expect(model.plan?.duplicates == 2)
    }

    @Test("Откат: счёт удаляется вместе с импортом, только если в нём нет других операций")
    func rollback() async throws {
        let model = makeModel()
        let observing = Task { await model.observeAccounts() }
        let observingBatches = Task { await model.observeBatches() }
        defer { observing.cancel(); observingBatches.cancel() }

        await model.open(try file())
        await model.confirm()
        try await waitUntil { model.batches.count == 1 && model.accounts.count == 1 }
        let batch = try #require(model.batches.first)
        #expect(batch.createdAccount)
        #expect(await model.canDeleteAccount(with: batch))

        // Операция, добавленная вручную, удалила бы вместе со счётом.
        try await transactions.save([
            FinanceTransaction(
                accountID: batch.accountID, bookedAt: Self.day,
                amount: Money(minorUnits: -100, currency: .byn), merchantRaw: "Вручную", source: .manual
            ),
        ])
        #expect(await !model.canDeleteAccount(with: batch))

        await model.rollback(batch)
        #expect(model.errorMessage == nil)
        try await waitUntil { model.batches.isEmpty }
        let left = try await transactions.transactions(TransactionQuery())
        #expect(left.map(\.merchantRaw) == ["Вручную"])
        #expect(model.accounts.count == 1)
    }

    @Test("Откат с удалением счёта, созданного импортом")
    func rollbackDeletingAccount() async throws {
        let model = makeModel()
        let observing = Task { await model.observeAccounts() }
        let observingBatches = Task { await model.observeBatches() }
        defer { observing.cancel(); observingBatches.cancel() }

        await model.open(try file())
        await model.confirm()
        try await waitUntil { model.batches.count == 1 && model.accounts.count == 1 }
        let batch = try #require(model.batches.first)

        await model.rollback(batch, deleteAccount: true)
        #expect(model.errorMessage == nil)
        try await waitUntil { model.batches.isEmpty && model.accounts.isEmpty }
        #expect(try await transactions.transactions(TransactionQuery()).isEmpty)
    }

    @Test("Банк не узнан: выбор вручную, затем превью")
    func chooseBank() async throws {
        let model = makeModel(FakeParser(score: 0.1, rows: Self.rows))
        await model.open(try file())
        #expect(model.phase == .choosingBank)
        let option = try #require(model.bankOptions.first)
        #expect(option.name == "Тестбанк")

        await model.choose(option)
        #expect(model.phase == .preview)
        #expect(model.plan?.newTransactions.count == 2)
    }

    @Test("Ошибки: неподдерживаемый файл и выписка без операций")
    func failures() async throws {
        let model = makeModel(FakeParser(rows: []))
        await model.open(try file("statement.xlsx"))
        #expect(model.phase == .failed("Поддерживаются выписки в PDF и CSV."))

        await model.open(try file())
        #expect(model.phase == .failed("В выписке нет операций."))
    }
}
