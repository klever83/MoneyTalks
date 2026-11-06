import Domain
import SwiftUI

extension Money {
    /// `-12,50 BYN` с учётом локали пользователя.
    public func formatted(locale: Locale = .current) -> String {
        decimalValue.formatted(.currency(code: currency.code).locale(locale))
    }
}

/// Сумма с цветом: доходы зелёные, расходы обычным цветом текста.
public struct MoneyText: View {
    private let money: Money

    public init(_ money: Money) {
        self.money = money
    }

    public var body: some View {
        Text(money.formatted())
            .monospacedDigit()
            .foregroundStyle(money.isNegative || money.isZero ? Color.primary : Color.income)
    }
}

extension Color {
    public static let income = Color.green
}
