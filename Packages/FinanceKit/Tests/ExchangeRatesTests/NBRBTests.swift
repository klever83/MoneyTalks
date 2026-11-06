@testable import ExchangeRates
import Domain
import Foundation
import Testing

@Suite("Курсы НБ РБ")
struct NBRBTests {
    @Test("Курс делится на масштаб")
    func decodeWithScale() throws {
        let json = #"{"Cur_ID":456,"Date":"2026-11-06T00:00:00","Cur_Abbreviation":"RUB","Cur_Scale":100,"Cur_Name":"Российских рублей","Cur_OfficialRate":3.8512}"#
        let rate = try NBRBExchangeRateProvider.decodeRate(from: Data(json.utf8))
        #expect(rate == Decimal(string: "0.038512"))
    }

    @Test("URL с датой по Минску")
    func url() {
        // 2026-11-05 22:30 UTC = 2026-11-06 01:30 в Минске.
        let date = Date(timeIntervalSince1970: 1_793_917_800)
        let url = NBRBExchangeRateProvider.url(for: .usd, on: date)
        #expect(url.absoluteString == "https://api.nbrb.by/exrates/rates/USD?parammode=2&ondate=2026-11-06")
    }
}
