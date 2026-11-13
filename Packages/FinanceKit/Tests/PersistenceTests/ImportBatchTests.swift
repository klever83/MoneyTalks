import Domain
import Foundation
import Persistence
import Testing

@Suite("Партии импорта")
struct ImportBatchTests {
    let database: AppDatabase
    let accounts: GRDBAccountRepository
    let transactions: GRDBTransactionRepository
    let imports: GRDBImportRepository

    init() throws {
        database = try AppDatabase.inMemory()
        accounts = GRDBAccountRepository(database: database)
        transactions = GRDBTransactionRepository(database: database)
        imports = GRDBImportRepository(database: database)
    }

    func firstValue<T>(_ stream: AsyncThrowingStream<T, any Error>) async throws -> T? {
        for try await value in stream { return value }
        return nil
    }

    @Test("Откат удаляет операции партии, снимает переводы и возвращает остаток")
    func rollback() async throws {
        // Сохранённое ранее пополнение другого счёта: импорт свяжет его переводом.
        let wallet = Account(name: "Вторая карта", kind: .card, currency: .byn)
        try await accounts.save(wallet)
        let incoming = FinanceTransaction(
            accountID: wallet.id, bookedAt: Date(timeIntervalSince1970: 2_000),
            amount: Money(minorUnits: 5_000, currency: .byn), merchantRaw: "Пополнение", source: .manual
        )
        try await transactions.save([incoming])

        let card = Account(
            name: "Карта", kind: .card, currency: .byn, openingBalance: Money(minorUnits: 90_000, currency: .byn)
        )
        try await accounts.save(Account(id: card.id, name: "Карта", kind: .card, currency: .byn,
                                        openingBalance: Money(minorUnits: 10_000, currency: .byn)))
        let batchID = UUID()
        let pairID = UUID()
        let purchase = FinanceTransaction(
            accountID: card.id, bookedAt: Date(timeIntervalSince1970: 1_000),
            amount: Money(minorUnits: -1_500, currency: .byn), merchantRaw: "Кофе",
            source: .imported, importBatchID: batchID, fingerprint: "h:1"
        )
        let transfer = FinanceTransaction(
            accountID: card.id, bookedAt: Date(timeIntervalSince1970: 2_000),
            amount: Money(minorUnits: -5_000, currency: .byn), merchantRaw: "Перевод", kind: .transfer,
            transferPairID: pairID, source: .imported, importBatchID: batchID, fingerprint: "h:2"
        )
        let batch = ImportBatch(
            id: batchID, accountID: card.id, bankName: "Тестбанк", fileName: "statement.pdf",
            fileHash: "abc", period: DateInterval(start: Date(timeIntervalSince1970: 0), duration: 86_400),
            transactionCount: 2, duplicateCount: 1, previousOpeningBalanceMinor: 10_000
        )
        // Импорт более ранней выписки заменил начальный остаток: 100 → 900.
        try await imports.commitImport(
            batch: batch, accounts: [card], transactions: [purchase, transfer],
            links: [TransferLink(transactionID: incoming.id, pairID: pairID)]
        )

        let listed = try #require(try await firstValue(imports.observeBatches()))
        #expect(listed.map(\.id) == [batchID])
        #expect(listed.first?.period == batch.period && listed.first?.duplicateCount == 1)
        #expect(try await imports.batch(fileHash: "abc")?.id == batchID)
        #expect(try await transactions.transactions(TransactionQuery(accountID: wallet.id)).first?.kind == .transfer)

        try await imports.rollback(batchID)

        // Остались только операции других выписок, пополнение снова доход.
        let left = try await transactions.transactions(TransactionQuery())
        #expect(left.map(\.id) == [incoming.id])
        #expect(left.first?.kind == .income && left.first?.transferPairID == nil)
        // Отпечатков нет: ту же выписку можно загрузить заново.
        #expect(try await transactions.fingerprints(accountID: card.id).isEmpty)
        #expect(try await firstValue(imports.observeBatches())?.isEmpty == true)
        #expect(try await imports.batch(fileHash: "abc") == nil)
        let balances = try #require(try await firstValue(accounts.observeBalances()))
        #expect(balances[card.id] == Money(minorUnits: 10_000, currency: .byn))

        // Повторный откат ничего не делает.
        try await imports.rollback(batchID)
    }

    @Test("Партии удалённого счёта не показываются")
    func deletedAccountBatches() async throws {
        let card = Account(name: "Карта", kind: .card, currency: .byn)
        try await imports.commitImport(
            batch: ImportBatch(id: UUID(), accountID: card.id, bankName: "Тестбанк", fileName: "a.pdf", transactionCount: 0),
            accounts: [card], transactions: [], links: []
        )
        #expect(try await firstValue(imports.observeBatches())?.count == 1)
        try await accounts.delete(card.id)
        #expect(try await firstValue(imports.observeBatches())?.isEmpty == true)
    }
}
