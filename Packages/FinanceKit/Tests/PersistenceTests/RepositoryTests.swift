import Domain
import Foundation
import Persistence
import Testing

@Suite("GRDB-репозитории")
struct RepositoryTests {
    let database: AppDatabase
    let accounts: GRDBAccountRepository
    let transactions: GRDBTransactionRepository
    let categories: GRDBCategoryRepository

    init() throws {
        database = try AppDatabase.inMemory()
        accounts = GRDBAccountRepository(database: database)
        transactions = GRDBTransactionRepository(database: database)
        categories = GRDBCategoryRepository(database: database)
    }

    @Test("Системные категории создаются миграцией")
    func systemCategoriesSeeded() async throws {
        let all = try await categories.categories()
        #expect(all.count >= 10)
        #expect(all.contains { $0.systemKey == "groceries" && $0.kind == .expense })
        #expect(all.contains { $0.systemKey == "salary" && $0.kind == .income })
    }

    @Test("ID системных категорий одинаковы в разных базах")
    func systemCategoryIDsAreStable() async throws {
        let other = GRDBCategoryRepository(database: try AppDatabase.inMemory())
        let first = try await categories.categories()
        let second = try await other.categories()
        for category in first {
            let key = try #require(category.systemKey)
            #expect(category.id == FinanceCategory.systemID(for: key))
            #expect(second.first { $0.systemKey == key }?.id == category.id)
        }
    }

    @Test("Удаление счёта скрывает его операции, операции других счетов остаются")
    func deletingAccountHidesItsTransactions() async throws {
        let card = Account(name: "Карта", kind: .card, currency: .byn)
        let cash = Account(name: "Наличные", kind: .cash, currency: .byn)
        try await accounts.save(card)
        try await accounts.save(cash)
        let onCard = FinanceTransaction(
            accountID: card.id, bookedAt: Date(timeIntervalSince1970: 1_000),
            amount: Money(minorUnits: -100, currency: .byn), merchantRaw: "A", source: .manual
        )
        let inCash = FinanceTransaction(
            accountID: cash.id, bookedAt: Date(timeIntervalSince1970: 2_000),
            amount: Money(minorUnits: -200, currency: .byn), merchantRaw: "B", source: .manual
        )
        try await transactions.save([onCard, inCash])

        try await accounts.delete(card.id)

        #expect(try await transactions.transactions(TransactionQuery()).map(\.id) == [inCash.id])
    }

    @Test("Операция сохраняется и читается без потерь")
    func roundTrip() async throws {
        let account = Account(name: "Карта", kind: .card, currency: .byn)
        try await accounts.save(account)

        let transaction = FinanceTransaction(
            accountID: account.id,
            bookedAt: Date(timeIntervalSince1970: 1_790_000_000),
            amount: Money(minorUnits: -1250, currency: .byn),
            originalAmount: Money(minorUnits: -399, currency: .eur),
            merchantRaw: "EVROOPT 123 MINSK BY",
            merchantNormalized: "Evroopt",
            mcc: 5411,
            source: .imported,
            fingerprint: "h:abc"
        )
        try await transactions.save([transaction])

        let loaded = try #require(try await transactions.transactions(TransactionQuery()).first)
        #expect(loaded.id == transaction.id)
        #expect(loaded.amount == transaction.amount)
        #expect(loaded.originalAmount == transaction.originalAmount)
        #expect(loaded.mcc == 5411)
        #expect(loaded.kind == .expense)
        #expect(loaded.bookedAt == transaction.bookedAt)
        #expect(try await transactions.fingerprints(accountID: account.id) == ["h:abc"])
    }

    @Test("Фильтр по периоду и мягкое удаление")
    func queryAndSoftDelete() async throws {
        let account = Account(name: "Наличные", kind: .cash, currency: .byn)
        try await accounts.save(account)
        let early = FinanceTransaction(
            accountID: account.id, bookedAt: Date(timeIntervalSince1970: 1_000),
            amount: Money(minorUnits: -100, currency: .byn), merchantRaw: "A", source: .manual
        )
        let late = FinanceTransaction(
            accountID: account.id, bookedAt: Date(timeIntervalSince1970: 100_000),
            amount: Money(minorUnits: -200, currency: .byn), merchantRaw: "B", source: .manual
        )
        try await transactions.save([early, late])

        let interval = DateInterval(start: Date(timeIntervalSince1970: 50_000), duration: 100_000)
        #expect(try await transactions.transactions(TransactionQuery(interval: interval)).map(\.id) == [late.id])

        try await transactions.delete(late.id)
        #expect(try await transactions.transactions(TransactionQuery()).map(\.id) == [early.id])
    }

    @Test("Импорт сохраняет счета и операции одной транзакцией")
    func commitImport() async throws {
        let imports = GRDBImportRepository(database: database)
        let account = Account(name: "Карта", kind: .card, currency: .byn)
        let transaction = FinanceTransaction(
            accountID: account.id, bookedAt: .now, amount: Money(minorUnits: -500, currency: .byn),
            merchantRaw: "Кофе", source: .imported, fingerprint: "h:1"
        )
        try await imports.commitImport(accounts: [account], transactions: [transaction])
        #expect(try await transactions.transactions(TransactionQuery(accountID: account.id)).map(\.id) == [transaction.id])
        #expect(try await transactions.fingerprints(accountID: account.id) == ["h:1"])

        // Операция на несуществующем счёте нарушает внешний ключ: не сохраняется ничего.
        let orphan = FinanceTransaction(
            accountID: Account.ID(), bookedAt: .now, amount: Money(minorUnits: -100, currency: .byn),
            merchantRaw: "Сирота", source: .imported
        )
        let second = Account(name: "Вторая", kind: .card, currency: .byn)
        await #expect(throws: (any Error).self) {
            try await imports.commitImport(accounts: [second], transactions: [orphan])
        }
        var names: [String] = []
        for try await list in accounts.observeAccounts() {
            names = list.map(\.name)
            break
        }
        #expect(names == ["Карта"])
    }
}
