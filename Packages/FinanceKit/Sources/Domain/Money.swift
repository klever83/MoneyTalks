import Foundation

public enum MoneyError: Error, Equatable, Sendable {
    case currencyMismatch(Currency, Currency)
}

/// Сумма в минимальных единицах валюты. Никаких `Double`.
public struct Money: Hashable, Codable, Sendable {
    public var minorUnits: Int64
    public var currency: Currency

    public init(minorUnits: Int64, currency: Currency) {
        self.minorUnits = minorUnits
        self.currency = currency
    }

    /// Создаёт сумму из десятичного значения с округлением до минимальной единицы (половина — от нуля).
    public init(_ value: Decimal, currency: Currency) {
        var scaled = value * Money.scale(for: currency)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        self.minorUnits = NSDecimalNumber(decimal: rounded).int64Value
        self.currency = currency
    }

    public static func zero(_ currency: Currency) -> Money {
        Money(minorUnits: 0, currency: currency)
    }

    public var decimalValue: Decimal {
        Decimal(minorUnits) / Money.scale(for: currency)
    }

    public var isNegative: Bool { minorUnits < 0 }
    public var isZero: Bool { minorUnits == 0 }
    public var negated: Money { Money(minorUnits: -minorUnits, currency: currency) }
    public var absolute: Money { Money(minorUnits: abs(minorUnits), currency: currency) }

    public func adding(_ other: Money) throws(MoneyError) -> Money {
        guard other.currency == currency else {
            throw .currencyMismatch(currency, other.currency)
        }
        return Money(minorUnits: minorUnits + other.minorUnits, currency: currency)
    }

    /// Пересчёт по курсу: `rate` — сколько единиц `target` стоит одна единица текущей валюты.
    public func converted(to target: Currency, rate: Decimal) -> Money {
        if target == currency { return self }
        return Money(decimalValue * rate, currency: target)
    }

    static func scale(for currency: Currency) -> Decimal {
        var result = Decimal(1)
        for _ in 0..<currency.minorUnitDigits { result *= 10 }
        return result
    }
}
