import Analytics
import Domain
import Foundation
import Testing

@Suite("Пересчёт в основную валюту")
struct CurrencyConversionTests {
    let interval = DateInterval(start: Date(timeIntervalSince1970: 0), duration: 86_400 * 31)
    let food = FinanceCategory.ID()

    func key(_ currency: Currency, _ day: String) -> ExchangeRateKey {
        ExchangeRateKey(currency: currency, day: day)
    }

    @Test("Курс на день, иначе ближайший ранний, иначе ближайший поздний; BYN всегда 1")
    func rateLookup() throws {
        let table = RateTable([
            key(.usd, "2026-10-05"): 3.2,
            key(.usd, "2026-10-07"): 3.3,
        ])
        #expect(table.rate(for: .usd, on: "2026-10-05")?.rate == 3.2)
        #expect(table.rate(for: .usd, on: "2026-10-05")?.isExact == true)
        let between = try #require(table.rate(for: .usd, on: "2026-10-06"))
        #expect(between.rate == 3.2 && !between.isExact)
        #expect(table.rate(for: .usd, on: "2026-10-09")?.rate == 3.3)
        #expect(table.rate(for: .usd, on: "2026-10-01")?.rate == 3.2)
        #expect(table.rate(for: .eur, on: "2026-10-05") == nil)
        #expect(table.rate(for: .byn, on: "2026-10-05")?.rate == 1)
    }

    @Test("Расходы в долларах пересчитываются по курсу на день и складываются с рублёвыми")
    func convertsToBYN() {
        let summary = CurrencyConversion.summary(
            interval: interval,
            base: .byn,
            totals: [CategoryTotal(categoryID: food, side: .expense, amount: Money(minorUnits: 1_000, currency: .byn))],
            daily: [
                DailyCategoryTotal(categoryID: food, side: .expense, amount: Money(minorUnits: 500, currency: .usd), day: "2026-10-05"),
                DailyCategoryTotal(categoryID: food, side: .expense, amount: Money(minorUnits: 100, currency: .usd), day: "2026-10-07"),
            ],
            rates: RateTable([key(.usd, "2026-10-05"): 3.2, key(.usd, "2026-10-07"): 3.3])
        )
        // 10 BYN + 5 USD × 3,2 + 1 USD × 3,3 = 29,30 BYN.
        #expect(summary.totals == [CategoryTotal(categoryID: food, side: .expense, amount: Money(minorUnits: 2_930, currency: .byn))])
        #expect(!summary.isApproximate && summary.missingRates.isEmpty)
    }

    @Test("Нет курса на день — ближайший и пометка; нет курса совсем — операция не входит в итог")
    func approximate() {
        let summary = CurrencyConversion.summary(
            interval: interval,
            base: .byn,
            totals: [],
            daily: [
                DailyCategoryTotal(categoryID: nil, side: .expense, amount: Money(minorUnits: 500, currency: .usd), day: "2026-10-06"),
                DailyCategoryTotal(categoryID: nil, side: .expense, amount: Money(minorUnits: 900, currency: .eur), day: "2026-10-06"),
            ],
            rates: RateTable([key(.usd, "2026-10-05"): 3.2])
        )
        #expect(summary.totals == [CategoryTotal(categoryID: nil, side: .expense, amount: Money(minorUnits: 1_600, currency: .byn))])
        #expect(summary.isApproximate)
        #expect(summary.missingRates == [key(.usd, "2026-10-06"), key(.eur, "2026-10-06")])
    }

    @Test("Основная валюта не BYN: рубли и евро пересчитываются через курс основной на тот же день")
    func convertsToUSD() {
        let summary = CurrencyConversion.summary(
            interval: interval,
            base: .usd,
            totals: [CategoryTotal(categoryID: food, side: .income, amount: Money(minorUnits: 200, currency: .usd))],
            daily: [
                DailyCategoryTotal(categoryID: food, side: .income, amount: Money(minorUnits: 3_200, currency: .byn), day: "2026-10-05"),
                DailyCategoryTotal(categoryID: food, side: .income, amount: Money(minorUnits: 1_000, currency: .eur), day: "2026-10-05"),
            ],
            rates: RateTable([key(.usd, "2026-10-05"): 3.2, key(.eur, "2026-10-05"): 3.52])
        )
        // 2 USD + 32 BYN / 3,2 + 10 EUR × 3,52 / 3,2 = 2 + 10 + 11 = 23 USD.
        #expect(summary.totals == [CategoryTotal(categoryID: food, side: .income, amount: Money(minorUnits: 2_300, currency: .usd))])
        #expect(!summary.isApproximate)
    }
}
