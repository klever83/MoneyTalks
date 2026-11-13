import Analytics
import Domain
import Foundation
import Persistence
import Testing

@Suite("Аналитика в SQL")
struct AnalyticsRepositoryTests {
    let database: AppDatabase
    let analytics: GRDBAnalyticsRepository
    let transactions: GRDBTransactionRepository
    let categories: GRDBCategoryRepository
    let account = Account(name: "Карта", kind: .card, currency: .byn)
    let groceries = FinanceCategory.systemID(for: "groceries")
    let salary = FinanceCategory.systemID(for: "salary")
    let month: DateInterval
    let calendar: Calendar

    init() async throws {
        database = try AppDatabase.inMemory()
        analytics = GRDBAnalyticsRepository(database: database)
        transactions = GRDBTransactionRepository(database: database)
        categories = GRDBCategoryRepository(database: database)
        try await GRDBAccountRepository(database: database).save(account)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Minsk"))
        self.calendar = calendar
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15)))
        month = try #require(calendar.dateInterval(of: .month, for: date))
    }

    func tx(
        _ minor: Int64,
        category: FinanceCategory.ID? = nil,
        currency: Currency = .byn,
        day: Int = 10,
        kind: FinanceTransaction.Kind? = nil,
        deleted: Bool = false
    ) throws -> FinanceTransaction {
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12)))
        return FinanceTransaction(
            accountID: account.id, bookedAt: date,
            amount: Money(minorUnits: minor, currency: currency),
            merchantRaw: "x", categoryID: category, kind: kind, source: .manual,
            deletedAt: deleted ? .now : nil
        )
    }

    func summary() async throws -> PeriodSummary {
        for try await summaries in analytics.observeSummaries([month]) {
            return try #require(summaries.first)
        }
        throw CancellationError()
    }

    @Test("Возвраты уменьшают расходы, переводы и удалённые не считаются, подкатегории сворачиваются")
    func totals() async throws {
        let food = FinanceCategory(name: "Еда", systemImage: "tag", colorHex: "#000000", kind: .expense)
        let lunch = FinanceCategory(name: "Обеды", systemImage: "tag", colorHex: "#000000", parentID: food.id, kind: .expense)
        try await categories.save(food)
        try await categories.save(lunch)

        try await transactions.save([
            try tx(-5000, category: groceries),
            try tx(1500, category: groceries),          // возврат
            try tx(-1000, category: lunch.id),
            try tx(-300, category: food.id),
            try tx(200_000, category: salary),
            try tx(-700),                               // без категории
            try tx(400),                                // без категории, доход
            try tx(-9999, kind: .transfer),
            try tx(-8888, category: groceries, deleted: true),
            try tx(-2000, category: groceries, currency: .usd),
            try tx(-7777, category: groceries, day: 1).with { $0.bookedAt = month.start.addingTimeInterval(-1) },
        ])

        let summary = try await summary()
        let byn = summary.incomeExpense(in: .byn)
        #expect(byn.expense.minorUnits == 3500 + 1300 + 700)
        #expect(byn.income.minorUnits == 200_400)
        let expenses = Dictionary(uniqueKeysWithValues: summary.expenses(in: .byn).map { ($0.categoryID, $0.amount.minorUnits) })
        #expect(expenses[groceries] == 3500)
        #expect(expenses[food.id] == 1300)
        #expect(expenses[nil] == 700)
        #expect(summary.incomeExpense(in: .usd).expense.minorUnits == 2000)
        #expect(summary.currencies == [.byn, .usd])
    }

    @Test("Итоги обновляются после изменения операций")
    func updates() async throws {
        var iterator = analytics.observeSummaries([month]).makeAsyncIterator()
        let empty = try #require(try await iterator.next())
        #expect(empty.first?.totals.isEmpty == true)
        try await transactions.save([try tx(-1000, category: groceries)])
        let updated = try #require(try await iterator.next())
        #expect(updated.first?.incomeExpense(in: .byn).expense.minorUnits == 1000)
    }

    @Test("Пересчёт в BYN по курсу на день из кэша; новый курс сразу пересчитывает итоги")
    func converted() async throws {
        let rates = GRDBExchangeRateRepository(database: database)
        try await transactions.save([
            try tx(-1000, category: groceries),
            try tx(-500, category: groceries, currency: .usd, day: 10),
            try tx(-200, category: groceries, currency: .usd, day: 12),
        ])
        try await rates.save([ExchangeRateKey(currency: .usd, day: "2026-10-10"): Decimal(string: "3.2")!])

        var iterator = analytics.observeSummaries([month], convertingTo: .byn).makeAsyncIterator()
        let first = try #require(try await iterator.next()?.first)
        // 12-го курса нет: берётся курс 10-го, итог приблизительный, курс 12-го просится к загрузке.
        #expect(first.incomeExpense(in: .byn).expense.minorUnits == 1000 + 1600 + 640)
        #expect(first.currencies == [.byn])
        #expect(first.isApproximate)
        #expect(first.missingRates == [ExchangeRateKey(currency: .usd, day: "2026-10-12")])

        try await rates.save([ExchangeRateKey(currency: .usd, day: "2026-10-12"): Decimal(string: "3.25")!])
        let second = try #require(try await iterator.next()?.first)
        #expect(second.incomeExpense(in: .byn).expense.minorUnits == 1000 + 1600 + 650)
        #expect(!second.isApproximate && second.missingRates.isEmpty)

        // Без пересчёта — по валютам, как раньше.
        let perCurrency = try await summary()
        #expect(perCurrency.currencies == [.byn, .usd])
    }
}

private extension FinanceTransaction {
    func with(_ change: (inout FinanceTransaction) -> Void) -> FinanceTransaction {
        var copy = self
        change(&copy)
        return copy
    }
}
