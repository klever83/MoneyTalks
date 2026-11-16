import Analytics
import Domain
@testable import FeatureAnalytics
import Foundation
import Persistence
import Testing

/// Ключи курсов, которые экран Обзора просил догрузить.
actor RateRequests {
    private(set) var calls: [Set<ExchangeRateKey>] = []

    func record(_ keys: Set<ExchangeRateKey>) {
        calls.append(keys)
    }
}

@MainActor
@Suite("Обзор: view model")
struct OverviewViewModelTests {
    let database: AppDatabase
    let transactions: GRDBTransactionRepository
    let account = Account(name: "Карта", kind: .card, currency: .byn)
    let requests: RateRequests
    let model: OverviewViewModel

    init() throws {
        database = try AppDatabase.inMemory()
        transactions = GRDBTransactionRepository(database: database)
        let requests = RateRequests()
        self.requests = requests
        model = OverviewViewModel(
            analytics: GRDBAnalyticsRepository(database: database),
            categories: GRDBCategoryRepository(database: database),
            loadRates: { keys in await requests.record(keys) }
        )
    }

    /// Ждёт, пока поток итогов доставит нужное состояние.
    func waitUntil(_ condition: () async -> Bool) async throws {
        var attempts = 0
        while await !condition(), attempts < 500 {
            try await Task.sleep(for: .milliseconds(10))
            attempts += 1
        }
        #expect(await condition())
    }

    func spend(_ minor: Int64, _ currency: Currency, at date: Date = .now) async throws {
        try await transactions.save([
            FinanceTransaction(
                accountID: account.id, bookedAt: date,
                amount: Money(minorUnits: -minor, currency: currency),
                merchantRaw: "Покупка", source: .manual
            ),
        ])
    }

    @Test("Итоги по каждой валюте: по умолчанию BYN, выбранная валюта переключает итоги")
    func perCurrency() async throws {
        try await GRDBAccountRepository(database: database).save(account)
        try await spend(1_000, .byn)
        try await spend(500, .usd)
        model.mode = .perCurrency
        let observing = Task { await model.observeSummaries() }
        defer { observing.cancel() }

        try await waitUntil { model.currencies == [.byn, .usd] }
        #expect(model.currency == .byn)
        #expect(model.totals.expense == Money(minorUnits: 1_000, currency: .byn))
        #expect(!model.isMonthEmpty)

        model.selectedCurrency = .usd
        #expect(model.currency == .usd)
        #expect(model.totals.expense == Money(minorUnits: 500, currency: .usd))
        #expect(model.history.count == OverviewViewModel.historyLength)
    }

    @Test("Пересчёт без курса: валюта не учтена, курс запрашивается один раз и после загрузки входит в итоги")
    func missingRates() async throws {
        try await GRDBAccountRepository(database: database).save(account)
        let day = Date.now
        try await spend(500, .usd, at: day)
        model.mode = .converted(to: .byn)
        let observing = Task { await model.observeSummaries() }
        defer { observing.cancel() }

        try await waitUntil { model.unconvertedCurrencies == [.usd] }
        #expect(model.currencies == [.byn])
        #expect(model.totals.expense.minorUnits == 0)
        let key = ExchangeRateKey(currency: .usd, date: day)
        try await waitUntil { await requests.calls == [[key]] }

        // Новые итоги без курса не запрашивают его снова.
        try await spend(1_000, .byn, at: day)
        try await waitUntil { model.totals.expense.minorUnits == 1_000 }
        #expect(await requests.calls == [[key]])

        // Курс появился в базе: итоги пересчитываются сами.
        try await GRDBExchangeRateRepository(database: database).save([key: Decimal(string: "3.2")!])
        try await waitUntil { model.unconvertedCurrencies.isEmpty }
        #expect(model.totals.expense == Money(minorUnits: 2_600, currency: .byn))
        #expect(!model.isApproximate)
        #expect(await requests.calls == [[key]])
    }

    @Test("Пустой месяц предлагает импорт; следующий месяц после текущего недоступен")
    func emptyMonthAndNavigation() async throws {
        let observing = Task { await model.observeSummaries() }
        defer { observing.cancel() }
        try await waitUntil { model.summaries.count == OverviewViewModel.historyLength }
        #expect(model.isMonthEmpty)
        #expect(model.slices.isEmpty)
        #expect(model.expenseChange == nil)

        #expect(model.isCurrentMonth)
        model.shiftMonth(by: -1)
        #expect(!model.isCurrentMonth)
        model.shiftMonth(by: 1)
        #expect(model.isCurrentMonth)
    }

    /// Экран переподписывается на итоги через `.task(id:)` при смене месяца; здесь то же вручную.
    @Test("Сдвиг на прошлый месяц: итоги и сравнение считаются по нему")
    func previousMonth() async throws {
        try await GRDBAccountRepository(database: database).save(account)
        let lastMonth = try #require(Calendar.current.date(byAdding: .month, value: -1, to: .now))
        try await spend(700, .byn, at: lastMonth)

        let current = Task { await model.observeSummaries() }
        try await waitUntil { model.summaries.count == OverviewViewModel.historyLength }
        #expect(model.isMonthEmpty)
        current.cancel()

        model.shiftMonth(by: -1)
        let previous = Task { await model.observeSummaries() }
        defer { previous.cancel() }
        try await waitUntil { model.totals.expense.minorUnits == 700 }
        #expect(!model.isMonthEmpty)
        #expect(model.history.last?.expense.minorUnits == 700)
    }
}
