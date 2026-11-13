import Domain
import Foundation
import GRDB
import Persistence
import Testing

@Suite("Резервная копия")
struct BackupTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("BackupTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func seeded() async throws -> (AppDatabase, Account) {
        let database = try AppDatabase.inMemory()
        let account = Account(name: "Карта", kind: .card, currency: .byn)
        try await GRDBAccountRepository(database: database).save(account)
        try await GRDBTransactionRepository(database: database).save([
            FinanceTransaction(
                accountID: account.id, bookedAt: Date(timeIntervalSince1970: 1_000),
                amount: Money(minorUnits: -500, currency: .byn), merchantRaw: "Кофе", source: .manual
            ),
        ])
        return (database, account)
    }

    @Test("Копия сохраняется в файл и восстанавливается в другую базу, экраны узнают об этом")
    func roundTrip() async throws {
        let (source, account) = try await seeded()
        let file = folder.appendingPathComponent("copy.sqlite")
        try await GRDBBackupService(database: source).exportBackup(to: file)

        let target = try AppDatabase.inMemory()
        let transactions = GRDBTransactionRepository(database: target)
        var iterator = transactions.observeTransactions(TransactionQuery()).makeAsyncIterator()
        #expect(try await iterator.next()?.isEmpty == true)

        try await GRDBBackupService(database: target).restoreBackup(from: file)
        let restored = try #require(try await iterator.next())
        #expect(restored.map(\.merchantRaw) == ["Кофе"])
        let accounts = try await GRDBAccountRepository(database: target).observeAccounts().first { _ in true }
        #expect(accounts?.map(\.id) == [account.id])
    }

    @Test("Не база MoneyTalks: ошибка, текущие данные на месте")
    func notBackup() async throws {
        let (target, _) = try await seeded()
        let text = folder.appendingPathComponent("notes.sqlite")
        try Data("просто текст".utf8).write(to: text)
        await #expect(throws: BackupError.notBackup) {
            try await GRDBBackupService(database: target).restoreBackup(from: text)
        }

        let other = folder.appendingPathComponent("other.sqlite")
        let queue = try DatabaseQueue(path: other.path)
        try await queue.write { try $0.execute(sql: "CREATE TABLE notes (id INTEGER)") }
        try queue.close()
        await #expect(throws: BackupError.notBackup) {
            try await GRDBBackupService(database: target).restoreBackup(from: other)
        }
        #expect(try await GRDBTransactionRepository(database: target).transactions(TransactionQuery()).count == 1)
    }

    @Test("Копия из более новой версии приложения не восстанавливается")
    func newerVersion() async throws {
        let (source, _) = try await seeded()
        let file = folder.appendingPathComponent("newer.sqlite")
        try await GRDBBackupService(database: source).exportBackup(to: file)
        let queue = try DatabaseQueue(path: file.path)
        try await queue.write { try $0.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v99-from-the-future')") }
        try queue.close()

        let target = try AppDatabase.inMemory()
        await #expect(throws: BackupError.newerVersion) {
            try await GRDBBackupService(database: target).restoreBackup(from: file)
        }
    }
}
