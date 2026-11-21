import Analytics
import Domain
import Foundation
import StatementImport
import Testing

@Suite("Снятие наличных")
struct CashWithdrawalsTests {
    let card = Account.ID()
    let start = Date(timeIntervalSince1970: 1_790_000_000)

    func transaction(_ minorUnits: Int64, _ description: String, mcc: Int? = nil, original: Money? = nil) -> FinanceTransaction {
        FinanceTransaction(
            accountID: card,
            bookedAt: start,
            amount: Money(minorUnits: minorUnits, currency: .byn),
            originalAmount: original,
            merchantRaw: description,
            mcc: mcc,
            source: .imported,
            fingerprint: "h:1"
        )
    }

    @Test("Снятие узнаётся по MCC и по описанию разных банков, безналичная оплата — нет")
    func recognizes() {
        #expect(CashWithdrawals.isCashOperation(transaction(-10_000, "Выдача наличных ATM TEST", mcc: 6011)))
        #expect(CashWithdrawals.isCashOperation(transaction(-4_500, "ATM BLR GOMEL ATM 181")))
        #expect(CashWithdrawals.isCashOperation(transaction(-382_000, "Cash BLR Minsk Dop.ofis 115")))
        // Касса допофиса в выписке Приорбанка по счёту.
        #expect(CashWithdrawals.isCashOperation(transaction(-285_000, "Dop fis 101-19 PRK 2 BLR, Minsk")))
        #expect(!CashWithdrawals.isCashOperation(transaction(-500, "DOPFISH SHOP BLR, MINSK")))
        #expect(CashWithdrawals.isCashOperation(transaction(-100_000, "MINSK Получение денег в банкомате RECATMALF")))
        #expect(!CashWithdrawals.isCashOperation(transaction(-1_145, "Безналичная оплата SHOP GREEN", mcc: 5411)))
        #expect(!CashWithdrawals.isCashOperation(transaction(-500, "Cashback партнёра")))
        #expect(!CashWithdrawals.isCashOperation(transaction(-500, "Retail BLR MINSK ATMOSFERA")))
        // Приорбанк, выписка по счёту: банкомат словом в названии, взнос через терминал.
        #expect(CashWithdrawals.isCashOperation(transaction(-20_000, "CBU-301/14 BAPB ATM BLR, GOMEL")))
        #expect(CashWithdrawals.isCashOperation(transaction(30_000, "CASH-IN 123 BLR, GOMEL")))
        #expect(CashWithdrawals.isCashOperation(transaction(250_000, "PST 456 BLR, MINSK")))
        #expect(CashWithdrawals.isCashOperation(transaction(100_000, "Взнос наличными")))
        // Банкомат другого банка с его кодом, в том числе в магазине («ALMI» не делает его покупкой).
        #expect(CashWithdrawals.isCashOperation(transaction(-5_000, "ATMTBK GM11 GOMEL TEST")))
        #expect(CashWithdrawals.isCashOperation(transaction(-5_000, "ATMALF GM08 ALMI")))
        #expect(!CashWithdrawals.isCashOperation(transaction(-500, "ATMOS BAR BLR, MINSK")))
        #expect(!CashWithdrawals.isCashOperation(transaction(-1_000, "PSTRUZHKA BLR, MINSK")))
        // MCC покупки важнее текста; списание с описанием взноса — не взнос.
        #expect(!CashWithdrawals.isCashOperation(transaction(-2_000, "CBU-301/14 BAPB ATM BLR, GOMEL", mcc: 5411)))
        #expect(!CashWithdrawals.isCashOperation(transaction(-2_000, "PST 456 BLR, MINSK")))
        #expect(!CashWithdrawals.isCashOperation(transaction(-2_000, "CASH-IN 123 BLR, GOMEL")))
    }

    @Test("Снятие становится переводом в кошелёк, в расходы не попадает")
    func pairsWithWallet() {
        let wallet = Account.ID()
        let withdrawal = transaction(-10_000, "Выдача наличных", mcc: 6011)
        let coffee = transaction(-500, "Кофе", mcc: 5814)
        let result = CashWithdrawals.pair([withdrawal, coffee]) { _ in wallet }

        #expect(result.transactions.map(\.kind) == [.transfer, .expense])
        let side = try! #require(result.walletTransactions.first)
        #expect(result.walletTransactions.count == 1)
        #expect(side.accountID == wallet)
        #expect(side.amount == Money(minorUnits: 10_000, currency: .byn))
        #expect(side.kind == .transfer)
        #expect(side.transferPairID != nil && side.transferPairID == result.transactions[0].transferPairID)
        #expect(side.fingerprint == "cash:h:1")
        #expect(Totals.byCurrency(result.transactions + result.walletTransactions)[.byn]?.expense.minorUnits == 500)
    }

    @Test("Снятие в другой валюте кладёт в кошелёк эту валюту")
    func foreignCash() {
        var currencies: [Currency] = []
        let result = CashWithdrawals.pair([
            transaction(-29_500, "ATM POL WARSZAWA", original: Money(minorUnits: -10_000, currency: .usd)),
        ]) { currency in
            currencies.append(currency)
            return Account.ID()
        }
        #expect(currencies == [.usd])
        #expect(result.walletTransactions.first?.amount == Money(minorUnits: 10_000, currency: .usd))
    }

    @Test("Внесение наличных через банкомат — перевод из кошелька")
    func deposit() {
        let result = CashWithdrawals.pair([transaction(20_000, "Взнос наличных через банкомат")]) { _ in Account.ID() }
        #expect(result.walletTransactions.first?.amount.minorUnits == -20_000)
    }

    @Test("Повторный вызов не создаёт вторую сторону, категория от пользователя не трогается")
    func idempotentAndRespectsLock() {
        let once = CashWithdrawals.pair([transaction(-10_000, "ATM BLR GOMEL")]) { _ in Account.ID() }
        let twice = CashWithdrawals.pair(once.transactions) { _ in Account.ID() }
        #expect(twice.walletTransactions.isEmpty)

        var locked = transaction(-10_000, "ATM BLR GOMEL")
        locked.categoryLocked = true
        #expect(CashWithdrawals.pair([locked]) { _ in Account.ID() }.walletTransactions.isEmpty)
    }

    @Test("Кошелёк: свой счёт наличных, если есть, иначе новый с постоянным идентификатором")
    func wallet() {
        let mine = Account(name: "Кошелёк", kind: .cash, currency: .byn)
        #expect(CashWithdrawals.wallet(for: .byn, among: [mine], name: "Наличные").id == mine.id)
        let usd = CashWithdrawals.wallet(for: .usd, among: [mine], name: "Наличные")
        #expect(usd.kind == .cash && usd.currency == .usd && usd.name == "Наличные")
        #expect(usd.id == CashWithdrawals.wallet(for: .usd, among: [], name: "Наличные").id)
    }

    @Test("Комиссия за снятие остаётся расходом, даже с MCC банкомата")
    func feeIsExpense() {
        #expect(!CashWithdrawals.isCashOperation(transaction(-150, "Комиссия за снятие наличных", mcc: 6011)))
        #expect(!CashWithdrawals.isCashOperation(transaction(-150, "Плата за выдачу наличных")))
        #expect(!CashWithdrawals.isCashOperation(transaction(-150, "ATM BLR GOMEL FEE")))
        let result = CashWithdrawals.pair([transaction(-150, "Комиссия за снятие наличных", mcc: 6011)]) { _ in Account.ID() }
        #expect(result.walletTransactions.isEmpty)
        #expect(result.transactions.first?.kind == .expense)
    }

    @Test("Удалённый кошелёк не воскрешается: новый получает другой идентификатор")
    func deletedWalletNotRevived() {
        var deleted = CashWithdrawals.wallet(for: .byn, among: [], name: "Наличные")
        deleted.deletedAt = start
        let fresh = CashWithdrawals.wallet(for: .byn, among: [deleted], name: "Наличные")
        #expect(fresh.id != deleted.id)
        #expect(fresh.deletedAt == nil)
        // Удалённый счёт может и не попасть в список счетов: тогда его передают отдельно.
        let other = CashWithdrawals.wallet(for: .byn, among: [], deletedIDs: [deleted.id], name: "Наличные")
        #expect(other.id != deleted.id)
    }
}
