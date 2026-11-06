import Domain

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

/// Чистые функции аналитики. Тяжёлые агрегаты позже переедут в SQL (GRDB),
/// а здесь останется пересчёт уже сгруппированных сумм.
public enum Totals {
    /// Итоги по каждой валюте без пересчёта. Переводы между своими счетами не учитываются.
    public static func byCurrency(_ transactions: [FinanceTransaction]) -> [Currency: IncomeExpense] {
        var result: [Currency: IncomeExpense] = [:]
        for transaction in transactions where transaction.kind != .transfer && transaction.deletedAt == nil {
            let currency = transaction.amount.currency
            var totals = result[currency] ?? IncomeExpense(currency: currency)
            if transaction.amount.isNegative {
                totals.expense.minorUnits += -transaction.amount.minorUnits
            } else {
                totals.income.minorUnits += transaction.amount.minorUnits
            }
            result[currency] = totals
        }
        return result
    }
}
