import Analytics
import Domain
import Foundation
import GRDB

/// Агрегаты аналитики в SQL: суммы по категориям верхнего уровня за период.
///
/// Сторона операции — по категории (#36): возврат с категорией расходов уменьшает расходы.
/// Подкатегории сворачиваются в родителя. Переводы и удалённые операции не учитываются.
/// С основной валютой операции в других валютах суммируются по дням и пересчитываются
/// по курсу НБ РБ на день (`CurrencyConversion`); курсы читаются в той же выборке.
public struct GRDBAnalyticsRepository: AnalyticsRepository {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func observeSummaries(
        _ intervals: [DateInterval], convertingTo base: Currency?
    ) -> AsyncThrowingStream<[PeriodSummary], any Error> {
        database.stream(ValueObservation.tracking { db in
            try intervals.map { try Self.summary(db, interval: $0, base: base) }
        })
    }

    /// Итоги одного периода. Отдельный метод, чтобы им пользовались и тесты, и бенчмарк (#12).
    static func summary(_ db: Database, interval: DateInterval, base: Currency? = nil) throws -> PeriodSummary {
        guard let base else {
            return PeriodSummary(interval: interval, totals: try totals(db, interval: interval))
        }
        let totals = try totals(db, interval: interval, onlyCurrency: base)
        let daily = try dailyTotals(db, interval: interval, exceptCurrency: base)
        var codes = Set(daily.map(\.amount.currency.code))
        if !daily.isEmpty { codes.insert(base.code) }
        codes.remove(Currency.byn.code)
        let rates = RateTable(try GRDBExchangeRateRepository.rates(db, currencies: codes))
        return CurrencyConversion.summary(interval: interval, base: base, totals: totals, daily: daily, rates: rates)
    }

    /// Минское время круглый год UTC+3, а `bookedAt` хранится в UTC: день курса — дата со сдвигом.
    private static let minskDay = "date(t.bookedAt, '+3 hours')"

    private static let side = """
        CASE
            WHEN c.kind IS NOT NULL THEN c.kind
            WHEN t.amountMinor < 0 THEN 'expense'
            ELSE 'income'
        END
        """

    private static let filter = """
        FROM transactions t
        LEFT JOIN categories c ON c.id = t.categoryID
        LEFT JOIN categories p ON p.id = c.parentID
        WHERE t.deletedAt IS NULL
          AND t.kind != 'transfer'
          AND t.bookedAt >= ? AND t.bookedAt < ?
        """

    /// Итоги в каждой валюте или только в одной.
    static func totals(_ db: Database, interval: DateInterval, onlyCurrency: Currency? = nil) throws -> [CategoryTotal] {
        var arguments: StatementArguments = [interval.start, interval.end]
        var currencyFilter = ""
        if let onlyCurrency {
            currencyFilter = "AND t.currencyCode = ?"
            arguments += [onlyCurrency.code]
        }
        let rows = try Row.fetchAll(db, sql: """
            SELECT t.currencyCode AS currencyCode,
                   t.currencyDigits AS currencyDigits,
                   COALESCE(p.id, c.id) AS categoryID,
                   \(side) AS side,
                   SUM(t.amountMinor) AS total
            \(filter)
            \(currencyFilter)
            GROUP BY t.currencyCode, t.currencyDigits, COALESCE(p.id, c.id), side
            """, arguments: arguments)
        return rows.compactMap { row -> CategoryTotal? in
            guard let side = FinanceCategory.Kind(rawValue: row["side"]) else { return nil }
            let currency = Currency(code: row["currencyCode"], minorUnitDigits: row["currencyDigits"])
            let sum: Int64 = row["total"]
            let categoryID: UUID? = row["categoryID"]
            return CategoryTotal(
                categoryID: categoryID.map { FinanceCategory.ID($0) },
                side: side,
                amount: Money(
                    minorUnits: AnalyticsSide.contribution(amount: Money(minorUnits: sum, currency: currency), side: side),
                    currency: currency
                )
            )
        }
    }

    /// Итоги в валютах, кроме `exceptCurrency`, по дням: их пересчитывают по курсу на день.
    static func dailyTotals(_ db: Database, interval: DateInterval, exceptCurrency: Currency) throws -> [DailyCategoryTotal] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT t.currencyCode AS currencyCode,
                   t.currencyDigits AS currencyDigits,
                   COALESCE(p.id, c.id) AS categoryID,
                   \(side) AS side,
                   \(minskDay) AS day,
                   SUM(t.amountMinor) AS total
            \(filter)
              AND t.currencyCode != ?
            GROUP BY t.currencyCode, t.currencyDigits, COALESCE(p.id, c.id), side, day
            """, arguments: [interval.start, interval.end, exceptCurrency.code])
        return rows.compactMap { row -> DailyCategoryTotal? in
            guard let side = FinanceCategory.Kind(rawValue: row["side"]) else { return nil }
            let currency = Currency(code: row["currencyCode"], minorUnitDigits: row["currencyDigits"])
            let sum: Int64 = row["total"]
            let categoryID: UUID? = row["categoryID"]
            return DailyCategoryTotal(
                categoryID: categoryID.map { FinanceCategory.ID($0) },
                side: side,
                amount: Money(
                    minorUnits: AnalyticsSide.contribution(amount: Money(minorUnits: sum, currency: currency), side: side),
                    currency: currency
                ),
                day: row["day"]
            )
        }
    }
}
