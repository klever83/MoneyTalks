import Domain
import Foundation
import GRDB

/// Кэш курсов НБ РБ (#10). Аналитика читает его в той же наблюдаемой выборке, поэтому
/// новые курсы сразу пересчитывают итоги на экране.
public struct GRDBExchangeRateRepository: ExchangeRateRepository {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func save(_ rates: [ExchangeRateKey: Decimal]) async throws {
        guard !rates.isEmpty else { return }
        let rows = rates.map { key, rate in (key.currency.code, key.day, "\(rate)") }
        try await database.writer.write { db in
            for (code, day, rate) in rows {
                try db.execute(
                    sql: "INSERT OR REPLACE INTO exchangeRates (currencyCode, day, bynRate) VALUES (?, ?, ?)",
                    arguments: [code, day, rate]
                )
            }
        }
    }

    /// Все известные курсы валют.
    static func rates(_ db: Database, currencies: Set<String>) throws -> [ExchangeRateKey: Decimal] {
        guard !currencies.isEmpty else { return [:] }
        let placeholders = Array(repeating: "?", count: currencies.count).joined(separator: ", ")
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT currencyCode, day, bynRate FROM exchangeRates WHERE currencyCode IN (\(placeholders))",
            arguments: StatementArguments(Array(currencies))
        )
        var result: [ExchangeRateKey: Decimal] = [:]
        for row in rows {
            let code: String = row["currencyCode"]
            let text: String = row["bynRate"]
            guard let rate = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else { continue }
            result[ExchangeRateKey(currency: Currency(code: code), day: row["day"])] = rate
        }
        return result
    }
}
