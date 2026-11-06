import Analytics
import Domain
import Foundation
import Testing

@Suite("Итоги")
struct TotalsTests {
    @Test("Итоги по валютам без переводов")
    func byCurrency() {
        let account = Account.ID()
        func tx(_ minor: Int64, _ currency: Currency, kind: FinanceTransaction.Kind? = nil) -> FinanceTransaction {
            FinanceTransaction(
                accountID: account, bookedAt: .now,
                amount: Money(minorUnits: minor, currency: currency),
                merchantRaw: "x", kind: kind, source: .manual
            )
        }
        let totals = Totals.byCurrency([
            tx(-1000, .byn), tx(-500, .byn), tx(300_000, .byn),
            tx(-2000, .byn, kind: .transfer),
            tx(-1500, .usd),
        ])
        #expect(totals[.byn]?.expense.minorUnits == 1500)
        #expect(totals[.byn]?.income.minorUnits == 300_000)
        #expect(totals[.byn]?.balance.minorUnits == 298_500)
        #expect(totals[.usd]?.expense.minorUnits == 1500)
    }
}
