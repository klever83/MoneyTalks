import Domain
import Foundation

public protocol ExchangeRateProvider: Sendable {
    /// Сколько единиц `to` стоит одна единица `from` на дату.
    func rate(from: Currency, to: Currency, on date: Date) async throws -> Decimal
}

/// Официальные курсы Национального банка Республики Беларусь (api.nbrb.by).
///
/// Кэширование курсов в базе — отдельная задача; сейчас каждый запрос идёт в сеть.
public struct NBRBExchangeRateProvider: ExchangeRateProvider {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func rate(from: Currency, to: Currency, on date: Date) async throws -> Decimal {
        if from == to { return 1 }
        let fromInBYN = try await bynRate(for: from, on: date)
        let toInBYN = try await bynRate(for: to, on: date)
        return fromInBYN / toInBYN
    }

    /// Сколько BYN стоит одна единица валюты.
    func bynRate(for currency: Currency, on date: Date) async throws -> Decimal {
        if currency == .byn { return 1 }
        let (data, _) = try await session.data(from: Self.url(for: currency, on: date))
        return try Self.decodeRate(from: data)
    }

    static func url(for currency: Currency, on date: Date) -> URL {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Minsk") ?? .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        var components = URLComponents(string: "https://api.nbrb.by/exrates/rates/\(currency.code)")!
        components.queryItems = [
            URLQueryItem(name: "parammode", value: "2"),
            URLQueryItem(name: "ondate", value: day),
        ]
        return components.url!
    }

    static func decodeRate(from data: Data) throws -> Decimal {
        struct Response: Decodable {
            let scale: Int
            let officialRate: Decimal

            enum CodingKeys: String, CodingKey {
                case scale = "Cur_Scale"
                case officialRate = "Cur_OfficialRate"
            }
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.officialRate / Decimal(response.scale)
    }
}
