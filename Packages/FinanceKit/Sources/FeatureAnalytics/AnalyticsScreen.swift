import Analytics
import Charts
import DesignSystem
import Domain
import SwiftUI

@MainActor
@Observable
final class OverviewViewModel {
    /// Сколько месяцев показывать на графике динамики.
    static let historyLength = 6

    /// Любой день выбранного месяца.
    var month: Date = .now
    var selectedCurrency: Currency?
    /// Пересчёт в основную валюту или итоги по каждой валюте (настройка).
    var mode: AmountDisplayMode = .converted(to: .byn)
    private(set) var summaries: [PeriodSummary] = []
    private(set) var categories: [FinanceCategory] = []
    var errorMessage: String?

    private let analytics: any AnalyticsRepository
    private let categoryRepository: any CategoryRepository
    private let calendar: Calendar
    private let loadRates: @Sendable (Set<ExchangeRateKey>) async -> Void
    /// Курсы, которые уже запрашивали: без сети или на день без курса не спрашиваем снова по кругу.
    private var requestedRates: Set<ExchangeRateKey> = []

    init(
        analytics: any AnalyticsRepository,
        categories: any CategoryRepository,
        calendar: Calendar = .current,
        loadRates: @escaping @Sendable (Set<ExchangeRateKey>) async -> Void = { _ in }
    ) {
        self.analytics = analytics
        categoryRepository = categories
        self.calendar = calendar
        self.loadRates = loadRates
    }

    var current: PeriodSummary? { summaries.last }
    var previous: PeriodSummary? { summaries.dropLast().last }

    /// Основная валюта, если итоги пересчитываются.
    var base: Currency? {
        if case let .converted(base) = mode { return base }
        return nil
    }

    /// Валюты, в которых были операции за показанные месяцы. При пересчёте — только основная.
    var currencies: [Currency] {
        if let base { return [base] }
        return Array(Set(summaries.flatMap(\.currencies))).sorted { $0.code < $1.code }
    }

    /// Пересчёт за показанные месяцы (и выбранный, и на графике) шёл не по точным курсам на день.
    var isApproximate: Bool { summaries.contains(where: \.isApproximate) }

    /// Валюты без единого курса: их операции за показанные месяцы в итоги не попали.
    var unconvertedCurrencies: [Currency] {
        Set(summaries.flatMap(\.unconvertedCurrencies)).sorted { $0.code < $1.code }
    }

    var currency: Currency {
        if let base { return base }
        if let selectedCurrency, currencies.contains(selectedCurrency) { return selectedCurrency }
        if currencies.contains(.byn) { return .byn }
        return currencies.first ?? .byn
    }

    var totals: IncomeExpense {
        current?.incomeExpense(in: currency) ?? IncomeExpense(currency: currency)
    }

    /// Изменение расходов к прошлому месяцу.
    var expenseChange: Double? {
        guard let previous else { return nil }
        return Totals.change(current: totals.expense, previous: previous.incomeExpense(in: currency).expense)
    }

    var slices: [ExpenseSlice] {
        ExpenseBreakdown.slices(current?.expenses(in: currency) ?? [])
    }

    /// Сумма срезов диаграммы: от неё считаются доли, поэтому она и стоит в центре.
    /// Может быть больше чистых расходов, если в какой-то категории возвраты перекрыли покупки.
    var slicesTotal: Money {
        Money(minorUnits: slices.reduce(Int64(0)) { $0 + $1.amount.minorUnits }, currency: currency)
    }

    /// За месяц нет ни одной операции: тогда уместно предложить импорт.
    var isMonthEmpty: Bool {
        current?.totals.isEmpty != false
    }

    var history: [(month: Date, expense: Money)] {
        summaries.map { ($0.interval.start, $0.incomeExpense(in: currency).expense) }
    }

    var isCurrentMonth: Bool {
        calendar.isDate(month, equalTo: .now, toGranularity: .month)
    }

    func category(for slice: ExpenseSlice) -> FinanceCategory? {
        slice.categoryID.flatMap { id in categories.first { $0.id == id } }
    }

    func shiftMonth(by value: Int) {
        guard let shifted = calendar.date(byAdding: .month, value: value, to: month) else { return }
        month = shifted
    }

    func observeSummaries() async {
        let months = Totals.months(endingAt: month, count: Self.historyLength, calendar: calendar)
        do {
            for try await items in analytics.observeSummaries(months, convertingTo: base) {
                summaries = items
                requestMissingRates(in: items)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Недостающие курсы догружаются в фоне; новые курсы в базе сами пересчитают итоги.
    private func requestMissingRates(in items: [PeriodSummary]) {
        let missing = items.reduce(into: Set<ExchangeRateKey>()) { $0.formUnion($1.missingRates) }
            .subtracting(requestedRates)
        guard !missing.isEmpty else { return }
        requestedRates.formUnion(missing)
        let loadRates = loadRates
        Task { await loadRates(missing) }
    }

    func observeCategories() async {
        do {
            for try await items in categoryRepository.observeCategories() {
                categories = items
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Главный экран: расходы и доходы за месяц, траты по категориям и динамика за полгода.
public struct AnalyticsScreen: View {
    @State private var model: OverviewViewModel
    @AppStorage(SettingsKey.convertToBaseCurrency) private var convertsToBase = true
    @AppStorage(SettingsKey.baseCurrencyCode) private var baseCurrencyCode = Currency.byn.code

    /// - Parameter loadRates: загрузка недостающих курсов НБ РБ в кэш.
    public init(
        analytics: any AnalyticsRepository,
        categories: any CategoryRepository,
        loadRates: @escaping @Sendable (Set<ExchangeRateKey>) async -> Void = { _ in }
    ) {
        _model = State(initialValue: OverviewViewModel(analytics: analytics, categories: categories, loadRates: loadRates))
    }

    private var mode: AmountDisplayMode {
        convertsToBase ? .converted(to: Currency(code: baseCurrencyCode)) : .perCurrency
    }

    private struct ObservationKey: Hashable {
        var month: Date
        var mode: AmountDisplayMode
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    monthSwitcher
                    if model.currencies.count > 1 {
                        Picker("Валюта", selection: Binding(
                            get: { model.currency },
                            set: { model.selectedCurrency = $0 }
                        )) {
                            ForEach(model.currencies) { Text($0.code).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section {
                    summary
                } footer: {
                    let unconverted = model.unconvertedCurrencies.map(\.code).joined(separator: ", ")
                    if !unconverted.isEmpty {
                        Text("Нет курса \(unconverted): операции в этой валюте не учтены. Курс загрузится при подключении к сети.")
                    } else if model.isApproximate {
                        Text("≈ Курса НБ РБ на часть дней ещё нет: пересчёт по ближайшему известному курсу.")
                    }
                }

                if model.slices.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "Расходов нет",
                            systemImage: "chart.pie",
                            description: model.isMonthEmpty
                                ? Text("Импортируйте выписку или добавьте операцию — здесь появятся траты по категориям")
                                : Text("В этом месяце расходов нет")
                        )
                    }
                } else {
                    Section("По категориям") {
                        donut
                        ForEach(model.slices) { slice in
                            SliceRow(slice: slice, category: model.category(for: slice))
                        }
                    }
                }

                if model.history.contains(where: { $0.expense.minorUnits > 0 }) {
                    Section("Расходы по месяцам") {
                        historyChart
                    }
                }
            }
            .navigationTitle("Обзор")
            .errorAlert($model.errorMessage)
            .task(id: ObservationKey(month: model.month, mode: mode)) {
                model.mode = mode
                await model.observeSummaries()
            }
            .task { await model.observeCategories() }
        }
    }

    private var monthSwitcher: some View {
        HStack {
            Button("Предыдущий месяц", systemImage: "chevron.left") { model.shiftMonth(by: -1) }
                .labelStyle(.iconOnly)
            Spacer()
            Text(model.month, format: .dateTime.month(.wide).year())
                .font(.headline)
            Spacer()
            Button("Следующий месяц", systemImage: "chevron.right") { model.shiftMonth(by: 1) }
                .labelStyle(.iconOnly)
                .disabled(model.isCurrentMonth)
        }
        .buttonStyle(.borderless)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Расходы").font(.subheadline).foregroundStyle(.secondary)
            Text(model.totals.expense.formatted())
                .font(.largeTitle.bold())
                .monospacedDigit()
            if let change = model.expenseChange {
                Text(change >= 0
                    ? "на \(change.formatted(.percent.precision(.fractionLength(0)))) больше, чем месяцем раньше"
                    : "на \((-change).formatted(.percent.precision(.fractionLength(0)))) меньше, чем месяцем раньше")
                    .font(.footnote)
                    .foregroundStyle(change > 0 ? Color.orange : Color.income)
            }
            Divider()
            LabeledContent("Доходы") { MoneyText(model.totals.income) }
            LabeledContent("Баланс") { MoneyText(model.totals.balance) }
        }
        .padding(.vertical, 4)
    }

    private var donut: some View {
        Chart(model.slices) { slice in
            SectorMark(
                angle: .value("Сумма", slice.amount.chartValue),
                innerRadius: .ratio(0.62),
                angularInset: 1.5
            )
            .cornerRadius(3)
            .foregroundStyle(SliceRow.color(for: slice, category: model.category(for: slice)))
        }
        .chartBackground { _ in
            VStack(spacing: 2) {
                Text("Всего").font(.caption).foregroundStyle(.secondary)
                Text(model.slicesTotal.formatted()).font(.headline).monospacedDigit()
            }
        }
        .frame(height: 220)
        .padding(.vertical, 8)
        .accessibilityLabel("Расходы по категориям")
    }

    private var historyChart: some View {
        Chart(model.history, id: \.month) { item in
            BarMark(
                x: .value("Месяц", item.month, unit: .month),
                y: .value("Расходы", item.expense.chartValue)
            )
            .foregroundStyle(
                Calendar.current.isDate(item.month, equalTo: model.month, toGranularity: .month)
                    ? Color.accentColor : Color.accentColor.opacity(0.35)
            )
            .cornerRadius(4)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
            }
        }
        .frame(height: 180)
        .padding(.vertical, 8)
    }
}

private struct SliceRow: View {
    let slice: ExpenseSlice
    let category: FinanceCategory?

    static func color(for slice: ExpenseSlice, category: FinanceCategory?) -> Color {
        if slice.isOther { return .gray.opacity(0.6) }
        return category?.color ?? .gray
    }

    private var title: String {
        if slice.isOther { return String(localized: "Остальное") }
        return category?.displayName ?? String(localized: "Без категории")
    }

    var body: some View {
        HStack {
            Image(systemName: slice.isOther ? "ellipsis.circle" : category?.systemImage ?? "questionmark.circle")
                .foregroundStyle(Self.color(for: slice, category: category))
                .frame(width: 28)
            Text(title)
            Spacer()
            VStack(alignment: .trailing) {
                Text(slice.amount.formatted()).monospacedDigit()
                Text(slice.share, format: .percent.precision(.fractionLength(0)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private extension Money {
    /// Значение для осей Swift Charts. Только для отрисовки: суммы считаются в `minorUnits`.
    var chartValue: Double {
        NSDecimalNumber(decimal: decimalValue).doubleValue
    }
}
