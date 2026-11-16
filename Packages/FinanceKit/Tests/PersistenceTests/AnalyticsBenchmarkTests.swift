import Analytics
import Domain
import Foundation
import GRDB
@testable import Persistence
import Testing

/// Бенчмарк аналитики (#12): 100 000 операций за два года, итоги Обзора за полгода.
/// Цель — десятки миллисекунд в релизной сборке. Тест собирается в отладке и идёт на общем
/// раннере CI, поэтому порог в нём с большим запасом: он ловит деградацию на порядки
/// (например, пропавший индекс), а точные цифры печатаются в лог.
@Suite("Бенчмарк аналитики", .serialized)
struct AnalyticsBenchmarkTests {
    static let count = 100_000
    static let months = 24

    let database: AppDatabase
    let calendar: Calendar
    let latest: Date

    init() async throws {
        database = try AppDatabase.inMemory()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Minsk"))
        self.calendar = calendar
        let start = try #require(calendar.date(from: DateComponents(year: 2024, month: 11, day: 1)))
        latest = try #require(calendar.date(byAdding: .month, value: Self.months, to: start)).addingTimeInterval(-1)

        let accounts = [
            Account(name: "Карта BYN", kind: .card, currency: .byn),
            Account(name: "Карта USD", kind: .card, currency: .usd),
            Account(name: "Наличные", kind: .cash, currency: .byn),
        ]
        for account in accounts {
            try await GRDBAccountRepository(database: database).save(account)
        }
        try await Self.seed(database.writer, accounts: accounts, from: start, to: latest)
    }

    /// Синтетические операции: 85 % расходов по категориям, доходы, переводы, валюта, удалённые.
    /// Генератор детерминированный, чтобы замеры были сравнимы между прогонами.
    static func seed(_ writer: any DatabaseWriter, accounts: [Account], from start: Date, to end: Date) async throws {
        try await writer.write { db in
            let categories = try Row.fetchAll(db, sql: "SELECT id, kind FROM categories")
            let expenses: [UUID] = categories.filter { ($0["kind"] as String) == "expense" }.map { $0["id"] }
            let incomes: [UUID] = categories.filter { ($0["kind"] as String) == "income" }.map { $0["id"] }
            let span = end.timeIntervalSince(start)
            var state: UInt64 = 0x9E37_79B9_7F4A_7C15
            func next() -> UInt64 {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return state >> 33
            }

            let statement = try db.makeStatement(sql: """
                INSERT INTO transactions (
                    id, accountID, bookedAt, amountMinor, currencyCode, currencyDigits,
                    merchantRaw, merchantNormalized, categoryID, kind, source,
                    createdAt, updatedAt, deletedAt
                ) VALUES (?, ?, ?, ?, ?, 2, ?, ?, ?, ?, 'imported', ?, ?, ?)
                """)
            for index in 0..<count {
                let bookedAt = start.addingTimeInterval(span * Double(next() % 1_000_000) / 1_000_000)
                let roll = next() % 100
                let account = roll < 10 ? accounts[1] : (roll < 15 ? accounts[2] : accounts[0])
                let kind: FinanceTransaction.Kind
                let amount: Int64
                let categoryID: UUID?
                switch next() % 100 {
                case 0..<85:
                    kind = .expense
                    amount = -Int64(100 + next() % 20_000)
                    categoryID = next() % 10 == 0 ? nil : expenses[Int(next() % UInt64(expenses.count))]
                case 85..<97:
                    kind = .income
                    amount = Int64(1_000 + next() % 300_000)
                    categoryID = incomes[Int(next() % UInt64(incomes.count))]
                default:
                    kind = .transfer
                    amount = -Int64(1_000 + next() % 50_000)
                    categoryID = nil
                }
                let merchant = "MERCHANT \(next() % 500)"
                try statement.execute(arguments: [
                    UUID(), account.id.rawValue, bookedAt, amount, account.currency.code,
                    merchant, merchant.lowercased(), categoryID, kind.rawValue,
                    bookedAt, bookedAt, index % 100 == 0 ? bookedAt : nil,
                ])
            }

            // Курс USD на каждый день, кроме каждого седьмого: часть дней пересчитывается по соседнему курсу.
            var day = start
            var dayIndex = 0
            while day <= end {
                if dayIndex % 7 != 0 {
                    try db.execute(
                        sql: "INSERT INTO exchangeRates (currencyCode, day, bynRate) VALUES ('USD', ?, ?)",
                        arguments: [ExchangeRateKey.day(for: day), "3.\(2_000 + dayIndex % 900)"]
                    )
                }
                day = day.addingTimeInterval(86_400)
                dayIndex += 1
            }
        }
    }

    /// Итоги за те же полгода, что показывает Обзор, и время их подсчёта (лучшее из нескольких прогонов).
    func measure(base: Currency?) async throws -> (summaries: [PeriodSummary], best: Duration) {
        let intervals = Totals.months(endingAt: latest, count: 6, calendar: calendar)
        var best = Duration.seconds(1_000)
        var summaries: [PeriodSummary] = []
        for _ in 0..<5 {
            let clock = ContinuousClock()
            let started = clock.now
            summaries = try await database.writer.read { db in
                try intervals.map { try GRDBAnalyticsRepository.summary(db, interval: $0, base: base) }
            }
            best = min(best, clock.now - started)
        }
        return (summaries, best)
    }

    @Test("Итоги по каждой валюте за полгода на 100 000 операций")
    func perCurrency() async throws {
        let (summaries, best) = try await measure(base: nil)
        print("Бенчмарк аналитики: по валютам, 6 месяцев, \(Self.count) операций — \(best)")
        #expect(summaries.count == 6)
        #expect(summaries.allSatisfy { !$0.totals.isEmpty })
        #expect(Set(summaries.flatMap(\.currencies)) == [.byn, .usd])
        #expect(best < .seconds(2))
    }

    @Test("Пересчёт в BYN по курсу на день за полгода на 100 000 операций")
    func converted() async throws {
        let (summaries, best) = try await measure(base: .byn)
        print("Бенчмарк аналитики: пересчёт в BYN, 6 месяцев, \(Self.count) операций — \(best)")
        #expect(summaries.count == 6)
        #expect(summaries.allSatisfy { $0.unconvertedCurrencies.isEmpty })
        #expect(summaries.contains { $0.isApproximate })
        #expect(summaries.allSatisfy { $0.currencies == [.byn] })
        #expect(best < .seconds(2))
    }

    @Test("Выборка итогов по периоду идёт по индексу даты, а не полным проходом")
    func usesDateIndex() async throws {
        let plan = try await database.writer.read { db in
            try Row.fetchAll(db, sql: """
                EXPLAIN QUERY PLAN
                SELECT t.currencyCode, SUM(t.amountMinor)
                FROM transactions t
                LEFT JOIN categories c ON c.id = t.categoryID
                LEFT JOIN categories p ON p.id = c.parentID
                WHERE t.deletedAt IS NULL
                  AND t.kind != 'transfer'
                  AND t.bookedAt >= ? AND t.bookedAt < ?
                GROUP BY t.currencyCode
                """, arguments: [latest.addingTimeInterval(-30 * 86_400), latest])
                .map { $0["detail"] as String }
        }
        print("План запроса итогов: \(plan)")
        #expect(plan.contains { $0.contains("transactions_booked_at") })
    }
}
