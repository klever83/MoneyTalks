import Foundation

/// Курс НБ РБ валюты на день: сколько BYN стоит одна единица валюты.
public struct ExchangeRateKey: Hashable, Sendable, Comparable {
    public var currency: Currency
    /// День в Минске, `yyyy-MM-dd`: так же его хранит база и так его понимает API НБ РБ.
    public var day: String

    public init(currency: Currency, day: String) {
        self.currency = currency
        self.day = day
    }

    public init(currency: Currency, date: Date) {
        self.init(currency: currency, day: Self.day(for: date))
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.currency.code, lhs.day) < (rhs.currency.code, rhs.day)
    }

    /// Курсы НБ РБ устанавливаются на день по минскому времени (UTC+3 круглый год).
    public static let minsk = TimeZone(identifier: "Europe/Minsk") ?? TimeZone(secondsFromGMT: 3 * 3_600)!

    public static func day(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = minsk
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Кэш курсов НБ РБ в базе (#10).
public protocol ExchangeRateRepository: Sendable {
    /// Сохраняет курсы (сколько BYN за единицу валюты), перезаписывая известные.
    func save(_ rates: [ExchangeRateKey: Decimal]) async throws
}
