import Domain
import Foundation

/// Итог категории за один день в валюте операций: сырьё для пересчёта в основную валюту.
public struct DailyCategoryTotal: Hashable, Sendable {
    public var categoryID: FinanceCategory.ID?
    public var side: FinanceCategory.Kind
    /// Расход или доход положительным числом (как в `CategoryTotal`).
    public var amount: Money
    /// День в Минске (`ExchangeRateKey.day`).
    public var day: String

    public init(categoryID: FinanceCategory.ID?, side: FinanceCategory.Kind, amount: Money, day: String) {
        self.categoryID = categoryID
        self.side = side
        self.amount = amount
        self.day = day
    }
}

/// Известные курсы НБ РБ: сколько BYN стоит единица валюты на день.
public struct RateTable: Sendable {
    /// Код валюты → курсы по дням, дни по возрастанию.
    private var byCurrency: [String: [(day: String, rate: Decimal)]] = [:]

    public init(_ rates: [ExchangeRateKey: Decimal]) {
        for (key, rate) in rates {
            byCurrency[key.currency.code, default: []].append((key.day, rate))
        }
        for code in byCurrency.keys {
            byCurrency[code]?.sort { $0.day < $1.day }
        }
    }

    /// Курс на день. Если его нет — ближайший более ранний, иначе ближайший более поздний,
    /// и `isExact == false`. `nil`, если курсов валюты нет совсем. Курс BYN всегда 1.
    public func rate(for currency: Currency, on day: String) -> (rate: Decimal, isExact: Bool)? {
        if currency == .byn { return (1, true) }
        guard let rates = byCurrency[currency.code], !rates.isEmpty else { return nil }
        // Первый день не раньше нужного.
        var low = 0
        var high = rates.count
        while low < high {
            let middle = (low + high) / 2
            if rates[middle].day < day { low = middle + 1 } else { high = middle }
        }
        if low < rates.count, rates[low].day == day { return (rates[low].rate, true) }
        if low > 0 { return (rates[low - 1].rate, false) }
        return (rates[low].rate, false)
    }
}

/// Пересчёт итогов в основную валюту по курсу НБ РБ на день операции (#10).
public enum CurrencyConversion {
    /// - Parameters:
    ///   - totals: итоги в основной валюте пересчёта не требуют и идут как есть.
    ///   - daily: итоги в других валютах по дням.
    public static func summary(
        interval: DateInterval,
        base: Currency,
        totals: [CategoryTotal],
        daily: [DailyCategoryTotal],
        rates: RateTable
    ) -> PeriodSummary {
        struct Key: Hashable {
            var categoryID: FinanceCategory.ID?
            var side: FinanceCategory.Kind
        }
        var sums: [Key: Int64] = [:]
        for total in totals where total.amount.currency == base {
            sums[Key(categoryID: total.categoryID, side: total.side), default: 0] += total.amount.minorUnits
        }
        var isApproximate = false
        var missing = Set<ExchangeRateKey>()
        for item in daily {
            let currency = item.amount.currency
            let source = rates.rate(for: currency, on: item.day)
            let target = rates.rate(for: base, on: item.day)
            if currency != .byn, source?.isExact != true {
                missing.insert(ExchangeRateKey(currency: currency, day: item.day))
            }
            if base != .byn, target?.isExact != true {
                missing.insert(ExchangeRateKey(currency: base, day: item.day))
            }
            guard let source, let target, target.rate != 0 else {
                // Курса нет совсем: операцию не во что пересчитать, итог неполный.
                isApproximate = true
                continue
            }
            if !source.isExact || !target.isExact { isApproximate = true }
            let converted = item.amount.converted(to: base, rate: source.rate / target.rate)
            sums[Key(categoryID: item.categoryID, side: item.side), default: 0] += converted.minorUnits
        }
        let result = sums
            .map { key, minor in CategoryTotal(categoryID: key.categoryID, side: key.side, amount: Money(minorUnits: minor, currency: base)) }
            .sorted { ($0.side.rawValue, $0.categoryID?.description ?? "") < ($1.side.rawValue, $1.categoryID?.description ?? "") }
        return PeriodSummary(interval: interval, totals: result, isApproximate: isApproximate, missingRates: missing)
    }
}
