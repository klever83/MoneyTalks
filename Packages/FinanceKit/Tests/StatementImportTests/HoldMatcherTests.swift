import Domain
import Foundation
@testable import StatementImport
import Testing

@Suite("Операции в обработке")
struct HoldMatcherTests {
    let account = Account(name: "БНБ", kind: .card, currency: .byn)
    let day: TimeInterval = 86_400
    let start = Date(timeIntervalSince1970: 1_790_000_000)

    func transaction(
        _ minorUnits: Int64, _ merchant: String, days: Double = 0, pending: Bool = false,
        original: Money? = nil, fingerprint: String? = nil
    ) -> FinanceTransaction {
        FinanceTransaction(
            accountID: account.id,
            bookedAt: start.addingTimeInterval(days * day),
            amount: Money(minorUnits: minorUnits, currency: .byn),
            originalAmount: original,
            merchantRaw: merchant,
            source: .imported,
            importBatchID: UUID(),
            fingerprint: fingerprint,
            isPending: pending
        )
    }

    @Test("Проведённая операция заменяет холд с той же суммой, сначала с тем же описанием")
    func replaces() {
        let coffee = transaction(-500, "COFFEE", pending: true)
        let shop = transaction(-500, "SHOP", days: 0.1, pending: true)
        let postedShop = transaction(-500, "SHOP", days: 2)
        let postedCoffee = transaction(-500, "COFFEE", days: 3)
        let resolution = HoldMatcher.resolve(
            new: [postedShop, postedCoffee], existing: [coffee, shop], statementFingerprints: [], period: nil
        )
        #expect(resolution.replaced == [postedShop.id: shop, postedCoffee.id: coffee])
        #expect(resolution.cancelled.isEmpty && resolution.alreadyPosted.isEmpty)
    }

    @Test("Сумма в валюте счёта при проведении изменилась: холд узнаётся по сумме покупки")
    func originalAmount() {
        let euro = Money(minorUnits: -1_000, currency: Currency(code: "EUR"))
        let hold = transaction(-3_510, "SHOP", pending: true, original: euro)
        let posted = transaction(-3_498, "SHOP", days: 1, original: euro)
        let resolution = HoldMatcher.resolve(new: [posted], existing: [hold], statementFingerprints: [], period: nil)
        #expect(resolution.replaced[posted.id] == hold)
    }

    @Test("Не холд, другой знак или дата вне окна — не замена")
    func mismatches() {
        let hold = transaction(-500, "SHOP", pending: true)
        let refund = transaction(500, "SHOP", days: 1)
        let late = transaction(-500, "SHOP", days: 20)
        let early = transaction(-500, "SHOP", days: -2)
        let resolution = HoldMatcher.resolve(
            new: [refund, late, early], existing: [hold, transaction(-500, "SHOP")], statementFingerprints: [], period: nil
        )
        #expect(resolution.replaced.isEmpty)
    }

    @Test("Холд, которого нет в выписке спустя месяц, отменён; свежий и всё ещё в обработке остаются")
    func cancels() {
        let old = transaction(-500, "OLD", pending: true, fingerprint: "ph:old")
        let stillPending = transaction(-700, "STILL", pending: true, fingerprint: "ph:still")
        let fresh = transaction(-900, "FRESH", days: 20, pending: true, fingerprint: "ph:fresh")
        let period = DateInterval(start: start.addingTimeInterval(-day), end: start.addingTimeInterval(40 * day))
        let resolution = HoldMatcher.resolve(
            new: [], existing: [old, stillPending, fresh], statementFingerprints: ["ph:still"], period: period
        )
        #expect(resolution.cancelled == [old])

        // Выписка не покрывает дату холда: судить о нём нельзя.
        let later = DateInterval(start: start.addingTimeInterval(day), end: start.addingTimeInterval(40 * day))
        #expect(HoldMatcher.resolve(new: [], existing: [old], statementFingerprints: [], period: later).cancelled.isEmpty)
    }

    @Test("Холд старой выписки, уже сохранённый проведённым, не импортируется")
    func alreadyPosted() {
        let posted = transaction(-500, "SHOP", days: 1)
        let hold = transaction(-500, "SHOP", pending: true)
        let manual = FinanceTransaction(
            accountID: account.id, bookedAt: start, amount: Money(minorUnits: -800, currency: .byn),
            merchantRaw: "Рынок", source: .manual
        )
        let manualHold = transaction(-800, "MARKET", pending: true)
        let resolution = HoldMatcher.resolve(
            new: [hold, manualHold], existing: [posted, manual], statementFingerprints: [], period: nil
        )
        // Ручная операция с той же суммой — не проведённый холд.
        #expect(resolution.alreadyPosted == [hold.id])
    }
}
