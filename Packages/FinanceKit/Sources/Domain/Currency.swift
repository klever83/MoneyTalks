/// Валюта по ISO 4217.
public struct Currency: Hashable, Codable, Sendable, Identifiable {
    public let code: String
    /// Сколько знаков после запятой у минимальной единицы (у BYN — 2, копейки).
    public let minorUnitDigits: Int

    public init(code: String, minorUnitDigits: Int = 2) {
        self.code = code.uppercased()
        self.minorUnitDigits = minorUnitDigits
    }

    public var id: String { code }

    public static let byn = Currency(code: "BYN")
    public static let usd = Currency(code: "USD")
    public static let eur = Currency(code: "EUR")
    public static let rub = Currency(code: "RUB")

    /// Валюты, доступные в MVP для счетов и как основная валюта отчётов.
    public static let supported: [Currency] = [.byn, .usd, .eur, .rub]
}
