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

@Suite("Возвраты и стороны (#36)")
struct RefundTests {
    let account = Account.ID()
    let groceries = FinanceCategory.ID()
    let salary = FinanceCategory.ID()

    func tx(_ minor: Int64, category: FinanceCategory.ID? = nil) -> FinanceTransaction {
        FinanceTransaction(
            accountID: account, bookedAt: .now,
            amount: Money(minorUnits: minor, currency: .byn),
            merchantRaw: "x", categoryID: category, source: .imported
        )
    }

    @Test("Возврат с категорией расходов уменьшает расходы и не попадает в доходы")
    func refundReducesExpense() {
        let totals = Totals.byCurrency(
            [tx(-5000, category: groceries), tx(1500, category: groceries), tx(200_000, category: salary), tx(700)],
            categoryKinds: [groceries: .expense, salary: .income]
        )
        #expect(totals[.byn]?.expense.minorUnits == 3500)
        #expect(totals[.byn]?.income.minorUnits == 200_700)
    }

    @Test("Сравнение с прошлым периодом")
    func change() {
        #expect(Totals.change(current: Money(minorUnits: 1200, currency: .byn), previous: Money(minorUnits: 1000, currency: .byn)) == 0.2)
        #expect(Totals.change(current: Money(minorUnits: 1200, currency: .byn), previous: .zero(.byn)) == nil)
    }

    @Test("Последние месяцы от старых к новым")
    func months() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Minsk"))
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 2, day: 15)))
        let months = Totals.months(endingAt: date, count: 3, calendar: calendar)
        #expect(months.map { calendar.component(.month, from: $0.start) } == [12, 1, 2])
        #expect(months.last?.contains(date) == true)
    }
}

@Suite("Круговая диаграмма расходов")
struct ExpenseBreakdownTests {
    func total(_ minor: Int64, side: FinanceCategory.Kind = .expense) -> CategoryTotal {
        CategoryTotal(categoryID: FinanceCategory.ID(), side: side, amount: Money(minorUnits: minor, currency: .byn))
    }

    @Test("Крупные категории отдельно, мелкие в «Остальное», доли в сумме дают 1")
    func slices() {
        let totals = [total(100), total(500), total(300), total(50), total(1000, side: .income), total(-20)]
        let slices = ExpenseBreakdown.slices(totals, limit: 2)
        #expect(slices.map(\.amount.minorUnits) == [500, 300, 150])
        #expect(slices.last?.isOther == true)
        #expect(abs(slices.map(\.share).reduce(0, +) - 1) < 0.000_001)
    }

    @Test("Нет расходов — нет диаграммы")
    func empty() {
        #expect(ExpenseBreakdown.slices([total(1000, side: .income), total(-50)]).isEmpty)
    }
}
