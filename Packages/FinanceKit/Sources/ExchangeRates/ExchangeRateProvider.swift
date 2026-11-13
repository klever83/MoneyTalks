import Domain
import Foundation

public protocol ExchangeRateProvider: Sendable {
    /// Сколько единиц `to` стоит одна единица `from` на дату.
    func rate(from: Currency, to: Currency, on date: Date) async throws -> Decimal
}

/// Официальные курсы Национального банка Республики Беларусь (api.nbrb.by).
/// Каждый запрос идёт в сеть; кэш в базе — `ExchangeRateLoader` и `ExchangeRateRepository`.
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
        try await bynRate(for: currency, day: ExchangeRateKey.day(for: date))
    }

    /// Сколько BYN стоит одна единица валюты на день `yyyy-MM-dd`.
    public func bynRate(for currency: Currency, day: String) async throws -> Decimal {
        if currency == .byn { return 1 }
        let (data, response) = try await session.data(from: Self.url(for: currency, day: day))
        // На неизвестную валюту или день без курса API отвечает 404 с пустым телом.
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return try Self.decodeRate(from: data)
    }

    static func url(for currency: Currency, on date: Date) -> URL {
        url(for: currency, day: ExchangeRateKey.day(for: date))
    }

    static func url(for currency: Currency, day: String) -> URL {
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
