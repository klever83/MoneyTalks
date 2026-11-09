import Analytics
import Domain
import Foundation
import GRDB

/// Агрегаты аналитики в SQL: суммы по категориям верхнего уровня за период.
///
/// Сторона операции — по категории (#36): возврат с категорией расходов уменьшает расходы.
/// Подкатегории сворачиваются в родителя. Переводы и удалённые операции не учитываются.
public struct GRDBAnalyticsRepository: AnalyticsRepository {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func observeSummaries(_ intervals: [DateInterval]) -> AsyncThrowingStream<[PeriodSummary], any Error> {
        database.stream(ValueObservation.tracking { db in
            try intervals.map { try Self.summary(db, interval: $0) }
        })
    }

    /// Итоги одного периода. Отдельный метод, чтобы им пользовались и тесты, и бенчмарк (#12).
    static func summary(_ db: Database, interval: DateInterval) throws -> PeriodSummary {
        let rows = try Row.fetchAll(db, sql: """
            SELECT t.currencyCode AS currencyCode,
                   t.currencyDigits AS currencyDigits,
                   COALESCE(p.id, c.id) AS categoryID,
                   CASE
                       WHEN c.kind IS NOT NULL THEN c.kind
                       WHEN t.amountMinor < 0 THEN 'expense'
                       ELSE 'income'
                   END AS side,
                   SUM(t.amountMinor) AS total
            FROM transactions t
            LEFT JOIN categories c ON c.id = t.categoryID
            LEFT JOIN categories p ON p.id = c.parentID
            WHERE t.deletedAt IS NULL
              AND t.kind != 'transfer'
              AND t.bookedAt >= ? AND t.bookedAt < ?
            GROUP BY t.currencyCode, t.currencyDigits, COALESCE(p.id, c.id), side
            """, arguments: [interval.start, interval.end])
        let totals = rows.compactMap { row -> CategoryTotal? in
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
        return PeriodSummary(interval: interval, totals: totals)
    }
}
