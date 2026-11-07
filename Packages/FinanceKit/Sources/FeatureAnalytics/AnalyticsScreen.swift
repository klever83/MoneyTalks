import Analytics
import DesignSystem
import Domain
import SwiftUI

@MainActor
@Observable
final class AnalyticsViewModel {
    private(set) var totals: [Currency: IncomeExpense] = [:]
    var errorMessage: String?
    private let repository: any TransactionRepository

    init(repository: any TransactionRepository) {
        self.repository = repository
    }

    var currencies: [Currency] {
        totals.keys.sorted { $0.code < $1.code }
    }

    /// Итоги текущего месяца по валютам. Пересчёт в основную валюту — отдельная задача (курсы НБ РБ).
    func observeCurrentMonth() async {
        guard let month = Calendar.current.dateInterval(of: .month, for: .now) else { return }
        do {
            for try await items in repository.observeTransactions(TransactionQuery(interval: month)) {
                totals = Totals.byCurrency(items)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

public struct AnalyticsScreen: View {
    @State private var model: AnalyticsViewModel

    public init(transactions: any TransactionRepository) {
        _model = State(initialValue: AnalyticsViewModel(repository: transactions))
    }

    public var body: some View {
        NavigationStack {
            List {
                ForEach(model.currencies) { currency in
                    if let totals = model.totals[currency] {
                        Section(currency.code) {
                            LabeledContent("Доходы") { MoneyText(totals.income) }
                            LabeledContent("Расходы") { MoneyText(totals.expense.negated) }
                            LabeledContent("Баланс") { MoneyText(totals.balance) }
                        }
                    }
                }
            }
            .overlay {
                if model.totals.isEmpty {
                    ContentUnavailableView(
                        "Нет данных за месяц",
                        systemImage: "chart.pie",
                        description: Text("Графики появятся, когда будут операции")
                    )
                }
            }
            .navigationTitle("Аналитика")
            .errorAlert($model.errorMessage)
            .task { await model.observeCurrentMonth() }
        }
    }
}
