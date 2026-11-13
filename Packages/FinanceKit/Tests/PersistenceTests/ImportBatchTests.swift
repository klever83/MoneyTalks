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

        let released = try await imports.rollback(batchID)
        #expect(released.map(\.id) == [incoming.id])
        #expect(released.first?.kind == .income && released.first?.categoryID == nil)

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
        #expect(try await imports.rollback(batchID).isEmpty)

        // Ту же выписку можно загрузить заново: идентификаторы операций те же, и сохранение
        // поднимает мягко удалённые строки.
        let again = ImportBatch(
            id: UUID(), accountID: card.id, bankName: "Тестбанк", fileName: "statement.pdf",
            fileHash: "abc", transactionCount: 2
        )
        try await imports.commitImport(batch: again, accounts: [], transactions: [purchase, transfer], links: [])
        #expect(Set(try await transactions.transactions(TransactionQuery(accountID: card.id)).map(\.id)) == [purchase.id, transfer.id])
        #expect(try await transactions.fingerprints(accountID: card.id) == ["h:1", "h:2"])
        #expect(try await imports.batch(fileHash: "abc")?.id == again.id)
        let reloaded = try #require(try await firstValue(accounts.observeBalances()))
        #expect(reloaded[card.id] == Money(minorUnits: 10_000 - 1_500 - 5_000, currency: .byn))
    }

    @Test("Откат не по порядку не портит остаток, поставленный позже")
    func rollbackOutOfOrder() async throws {
        func money(_ minor: Int64) -> Money { Money(minorUnits: minor, currency: .byn) }
        var card = Account(name: "Карта", kind: .card, currency: .byn, openingBalance: money(10_000))
        try await accounts.save(card)
        func importBatch(applying applied: Int64, previous: Int64) async throws -> UUID {
            card.openingBalance = money(applied)
            let id = UUID()
            try await imports.commitImport(
                batch: ImportBatch(
                    id: id, accountID: card.id, bankName: "Тестбанк", fileName: "\(applied).pdf", transactionCount: 0,
                    previousOpeningBalanceMinor: previous, appliedOpeningBalanceMinor: applied
                ),
                accounts: [card], transactions: [], links: []
            )
            return id
        }
        // Сентябрь, затем август: каждая выписка раньше предыдущей и заменяет остаток.
        let september = try await importBatch(applying: 20_000, previous: 10_000)
        let august = try await importBatch(applying: 30_000, previous: 20_000)

        // Откат сентября: остаток уже поставил август, он новее и остаётся.
        try await imports.rollback(september)
        #expect(try await firstValue(accounts.observeBalances())?[card.id] == money(30_000))

        // Откат августа: остаток с его импорта не менялся. Возвращается остаток до обоих импортов,
        // потому что откат сентября передал августу свой прежний.
        try await imports.rollback(august)
        #expect(try await firstValue(accounts.observeBalances())?[card.id] == money(10_000))
    }

    @Test("Партии удалённого счёта не показываются")
    func deletedAccountBatches() async throws {
        let card = Account(name: "Карта", kind: .card, currency: .byn)
        try await imports.commitImport(
            batch: ImportBatch(id: UUID(), accountID: card.id, bankName: "Тестбанк", fileName: "a.pdf", fileHash: "a", transactionCount: 0),
            accounts: [card], transactions: [], links: []
        )
        #expect(try await firstValue(imports.observeBatches())?.count == 1)
        try await accounts.delete(card.id)
        #expect(try await firstValue(imports.observeBatches())?.isEmpty == true)
        // Повторная загрузка того же файла после удаления счёта — не повтор.
        #expect(try await imports.batch(fileHash: "a") == nil)
    }
}
