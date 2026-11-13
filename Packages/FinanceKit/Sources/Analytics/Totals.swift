import Domain
import Foundation

/// Доходы и расходы в одной валюте.
public struct IncomeExpense: Hashable, Sendable {
    public var income: Money
    public var expense: Money

    public init(currency: Currency) {
        income = .zero(currency)
        expense = .zero(currency)
    }

    public var balance: Money {
        Money(minorUnits: income.minorUnits - expense.minorUnits, currency: income.currency)
    }
}

/// Сторона операции в аналитике (#36): по категории, а не по знаку суммы.
/// Возврат покупки (плюс с категорией расходов) уменьшает расходы, а не попадает в доходы.
/// Без категории решает знак: минус — расход, плюс — доход.
public enum AnalyticsSide {
    public static func kind(amount: Money, categoryKind: FinanceCategory.Kind?) -> FinanceCategory.Kind {
        categoryKind ?? (amount.isNegative ? .expense : .income)
    }

    /// Вклад операции в свою сторону: расход положительный, возврат в расходах отрицательный.
    public static func contribution(amount: Money, side: FinanceCategory.Kind) -> Int64 {
        side == .expense ? -amount.minorUnits : amount.minorUnits
    }
}

/// Сумма по категории верхнего уровня за период. `categoryID == nil` — операции без категории.
public struct CategoryTotal: Hashable, Sendable {
    public var categoryID: FinanceCategory.ID?
    public var side: FinanceCategory.Kind
    /// Расход или доход положительным числом; может быть отрицательным, если возвраты больше покупок.
    public var amount: Money

    public init(categoryID: FinanceCategory.ID?, side: FinanceCategory.Kind, amount: Money) {
        self.categoryID = categoryID
        self.side = side
        self.amount = amount
    }
}

/// Итоги периода: суммы по категориям верхнего уровня, по каждой валюте отдельно
/// или пересчитанные в основную валюту (`CurrencyConversion`).
public struct PeriodSummary: Hashable, Sendable {
    public var interval: DateInterval
    public var totals: [CategoryTotal]
    /// Пересчёт шёл не везде по курсу на день операции: курса на день ещё нет, взят ближайший известный.
    public var isApproximate: Bool
    /// Валюты, для которых нет ни одного курса: их операции в итог не попали, он неполный.
    public var unconvertedCurrencies: Set<Currency>
    /// Курсы, которых не хватило для точного пересчёта: их стоит загрузить.
    public var missingRates: Set<ExchangeRateKey>

    public init(
        interval: DateInterval,
        totals: [CategoryTotal],
        isApproximate: Bool = false,
        unconvertedCurrencies: Set<Currency> = [],
        missingRates: Set<ExchangeRateKey> = []
    ) {
        self.interval = interval
        self.totals = totals
        self.isApproximate = isApproximate
        self.unconvertedCurrencies = unconvertedCurrencies
        self.missingRates = missingRates
    }

    public var currencies: [Currency] {
        Array(Set(totals.map(\.amount.currency))).sorted { $0.code < $1.code }
    }

    public func incomeExpense(in currency: Currency) -> IncomeExpense {
        var result = IncomeExpense(currency: currency)
        for total in totals where total.amount.currency == currency {
            switch total.side {
            case .expense: result.expense.minorUnits += total.amount.minorUnits
            case .income: result.income.minorUnits += total.amount.minorUnits
            }
        }
        return result
    }

    /// Расходы по категориям в валюте, от больших к меньшим.
    public func expenses(in currency: Currency) -> [CategoryTotal] {
        totals
            .filter { $0.side == .expense && $0.amount.currency == currency }
            .sorted { $0.amount.minorUnits > $1.amount.minorUnits }
    }
}

/// Итоги нескольких периодов с обновлением после каждого изменения операций (и курсов).
public protocol AnalyticsRepository: Sendable {
    /// Для каждого интервала — итоги по категориям верхнего уровня. Переводы и удалённые операции не учитываются.
    /// - Parameter base: основная валюта: всё пересчитывается в неё по курсу НБ РБ на день операции.
    ///   `nil` — итоги по каждой валюте отдельно.
    func observeSummaries(_ intervals: [DateInterval], convertingTo base: Currency?) -> AsyncThrowingStream<[PeriodSummary], any Error>
}

public extension AnalyticsRepository {
    func observeSummaries(_ intervals: [DateInterval]) -> AsyncThrowingStream<[PeriodSummary], any Error> {
        observeSummaries(intervals, convertingTo: nil)
    }
}

/// Чистые функции аналитики для уже загруженных операций. Агрегаты по базе считает `AnalyticsRepository` в SQL.
public enum Totals {
    /// Итоги по каждой валюте без пересчёта. Переводы между своими счетами не учитываются,
    /// сторона определяется по категории (`AnalyticsSide`).
    public static func byCurrency(
        _ transactions: [FinanceTransaction],
        categoryKinds: [FinanceCategory.ID: FinanceCategory.Kind] = [:]
    ) -> [Currency: IncomeExpense] {
        var result: [Currency: IncomeExpense] = [:]
        for transaction in transactions where transaction.kind != .transfer && transaction.deletedAt == nil {
            let currency = transaction.amount.currency
            var totals = result[currency] ?? IncomeExpense(currency: currency)
            let side = AnalyticsSide.kind(
                amount: transaction.amount,
                categoryKind: transaction.categoryID.flatMap { categoryKinds[$0] }
            )
            let value = AnalyticsSide.contribution(amount: transaction.amount, side: side)
            switch side {
            case .expense: totals.expense.minorUnits += value
            case .income: totals.income.minorUnits += value
            }
            result[currency] = totals
        }
        return result
    }

    /// Изменение относительно прошлого периода: `0.12` — на 12% больше. `nil`, если сравнивать не с чем.
    public static func change(current: Money, previous: Money) -> Double? {
        guard previous.minorUnits > 0, current.currency == previous.currency else { return nil }
        return Double(current.minorUnits - previous.minorUnits) / Double(previous.minorUnits)
    }

    /// Последние `count` месяцев, заканчивая месяцем `date`, от старых к новым.
    public static func months(endingAt date: Date, count: Int, calendar: Calendar = .current) -> [DateInterval] {
        guard let current = calendar.dateInterval(of: .month, for: date) else { return [] }
        return (0..<count).reversed().compactMap { offset in
            calendar.date(byAdding: .month, value: -offset, to: current.start)
                .flatMap { calendar.dateInterval(of: .month, for: $0) }
        }
    }
}

/// Доля категории в расходах для круговой диаграммы.
public struct ExpenseSlice: Hashable, Sendable, Identifiable {
    /// `nil` у операций без категории; `isOther` — свёрнутые мелкие категории.
    public var categoryID: FinanceCategory.ID?
    public var isOther: Bool
    public var amount: Money
    /// Доля от всех расходов периода, 0…1.
    public var share: Double

    public var id: String {
        isOther ? "other" : categoryID?.description ?? "uncategorized"
    }
}

public enum ExpenseBreakdown {
    /// Расходы по категориям от больших к меньшим: первые `limit` отдельно, остальные одним «Остальное».
    /// Категории, где возвраты перекрыли покупки (сумма ≤ 0), в диаграмму не попадают.
    public static func slices(_ totals: [CategoryTotal], limit: Int = 6) -> [ExpenseSlice] {
        let positive = totals
            .filter { $0.side == .expense && $0.amount.minorUnits > 0 }
            .sorted { $0.amount.minorUnits > $1.amount.minorUnits }
        guard let currency = positive.first?.amount.currency else { return [] }
        let sum = positive.reduce(Int64(0)) { $0 + $1.amount.minorUnits }
        func share(_ minor: Int64) -> Double { Double(minor) / Double(sum) }

        var slices = positive.prefix(limit).map { total in
            ExpenseSlice(categoryID: total.categoryID, isOther: false, amount: total.amount, share: share(total.amount.minorUnits))
        }
        let rest = positive.dropFirst(limit).reduce(Int64(0)) { $0 + $1.amount.minorUnits }
        if rest > 0 {
            slices.append(ExpenseSlice(
                categoryID: nil, isOther: true,
                amount: Money(minorUnits: rest, currency: currency), share: share(rest)
            ))
        }
        return slices
    }
}
