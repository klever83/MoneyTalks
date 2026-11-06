import Analytics
import Domain
import Foundation
import StatementImport
import Testing

@Suite("Переводы между своими счетами")
struct TransferMatcherTests {
    let card = Account.ID()
    let deposit = Account.ID()
    let usd = Account.ID()
    let start = Date(timeIntervalSince1970: 1_790_000_000)

    func transaction(
        _ account: Account.ID, _ minorUnits: Int64, _ description: String = "Перевод",
        currency: Currency = .byn, hours: Double = 0, original: Money? = nil
    ) -> FinanceTransaction {
        FinanceTransaction(
            accountID: account,
            bookedAt: start.addingTimeInterval(hours * 3_600),
            amount: Money(minorUnits: minorUnits, currency: currency),
            originalAmount: original,
            merchantRaw: description,
            source: .imported
        )
    }

    @Test("Списание и зачисление на ту же сумму на разных счетах — перевод, в расходы не попадает")
    func pairsAcrossAccounts() {
        let out = transaction(card, -10_000)
        let into = transaction(deposit, 10_000, hours: 30)
        let coffee = transaction(card, -500, "Кофе", hours: 1)
        let pairs = TransferMatcher.pairs(in: [out, coffee, into])
        #expect(pairs == [TransferMatcher.Pair(outgoing: out.id, incoming: into.id)])

        let marked = TransferMatcher.apply(pairs, to: [out, coffee, into])
        #expect(marked.map(\.kind) == [.transfer, .expense, .transfer])
        #expect(marked[0].transferPairID != nil && marked[0].transferPairID == marked[2].transferPairID)
        #expect(Totals.byCurrency(marked)[.byn]?.expense.minorUnits == 500)
        #expect(Totals.byCurrency(marked)[.byn]?.income.minorUnits == 0)
    }

    @Test("Вне окна в три дня пары нет")
    func outsideWindow() {
        let pairs = TransferMatcher.pairs(in: [transaction(card, -10_000), transaction(deposit, 10_000, hours: 80)])
        #expect(pairs.isEmpty)
    }

    @Test("В одном счёте покупка и возврат на ту же сумму — не перевод")
    func refundIsNotTransfer() {
        let pairs = TransferMatcher.pairs(in: [
            transaction(card, -2_500, "Retail BLR MINSK SHOP"),
            transaction(card, 2_500, "Retail BLR MINSK SHOP", hours: 2),
        ])
        #expect(pairs.isEmpty)
    }

    @Test("В одном счёте пара с общим номером документа — перевод (контракт и карта)")
    func sameAccountWithReference() {
        let into = transaction(card, 250_000, "Поступление на контракт клиента 000000-00000-000001")
        let out = transaction(card, -250_000, "Payment From Client Contract 000000-00000-000001")
        let other = transaction(card, -250_000, "Payment From Client Contract 000000-00000-000002")
        #expect(TransferMatcher.pairs(in: [into, other, out]) == [TransferMatcher.Pair(outgoing: out.id, incoming: into.id)])
    }

    @Test("Обмен валют: сумма в валюте операции совпадает со второй стороной")
    func currencyExchange() {
        let out = transaction(card, -29_500, original: Money(minorUnits: -10_000, currency: .usd))
        let into = transaction(usd, 10_000, currency: .usd, hours: 1)
        #expect(TransferMatcher.pairs(in: [out, into]) == [TransferMatcher.Pair(outgoing: out.id, incoming: into.id)])
        // Без суммы в валюте операции разные валюты не сравнить: пары нет.
        #expect(TransferMatcher.pairs(in: [transaction(card, -29_500), into]).isEmpty)
    }

    @Test("Ближайшая по времени пара выигрывает, равноудалённые на разных счетах не угадываются")
    func closestAndAmbiguous() {
        let out = transaction(card, -5_000)
        let near = transaction(deposit, 5_000, hours: 1)
        let far = transaction(usd, 5_000, hours: 20)
        #expect(TransferMatcher.pairs(in: [out, far, near]) == [TransferMatcher.Pair(outgoing: out.id, incoming: near.id)])

        let twin = transaction(usd, 5_000, hours: 1)
        #expect(TransferMatcher.pairs(in: [out, near, twin]).isEmpty)
    }

    @Test("Два одинаковых перевода между теми же счетами склеиваются оба")
    func repeatedTransfers() {
        let pairs = TransferMatcher.pairs(in: [
            transaction(card, -5_000), transaction(card, -5_000, hours: 2),
            transaction(deposit, 5_000, hours: 1), transaction(deposit, 5_000, hours: 3),
        ])
        #expect(pairs.count == 2)
    }

    @Test("Категория от пользователя, удалённые и уже связанные операции не трогаются")
    func skipsLockedDeletedAndPaired() {
        var locked = transaction(card, -10_000)
        locked.categoryLocked = true
        var deleted = transaction(card, -10_000)
        deleted.deletedAt = start
        var paired = transaction(card, -10_000)
        paired.transferPairID = UUID()
        paired.kind = .transfer
        #expect(TransferMatcher.pairs(in: [locked, deleted, paired, transaction(deposit, 10_000)]).isEmpty)
    }

    @Test("Идентификатор пары одинаковый при повторном поиске")
    func stablePairID() {
        let out = transaction(card, -10_000)
        let into = transaction(deposit, 10_000)
        #expect(TransferMatcher.pairs(in: [out, into]).first?.id == TransferMatcher.pairs(in: [into, out]).first?.id)
    }
}
