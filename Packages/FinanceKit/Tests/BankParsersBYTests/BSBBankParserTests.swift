import BankParsersBY
import Domain
import Foundation
import StatementImport
import Testing

@Suite("БСБ Банк")
struct BSBBankParserTests {
    /// Разметка как у выписки по счёту клиента, данные выдуманные. Суммы без знака,
    /// ячейки по центру строки: часть описания выше строки с датой, часть ниже.
    static func statement(debited: String = "124.0") -> PDFFixture {
        var pdf = PDFFixture()
        pdf.pageSize = CGSize(width: 1191, height: 1684)
        pdf.fontSize = 11
        pdf.text("ЗАО «БСБ-Банк»", x: 60, y: 126)
        pdf.text("ВЫПИСКА ПО СЧЕТУ КЛИЕНТА с 2026-10-09 по 2026-11-07", x: 60, y: 187)
        pdf.text("Валюта карт-счета: BYN", x: 60, y: 248)

        let header: [(String, CGFloat, CGFloat)] = [
            ("4 последние", 282, 307), ("Сумма в", 947, 307),
            ("Валюта", 726, 315), ("Сумма", 836, 315), ("Остаток карт-", 1051, 315),
            ("Дата операции", 64, 323), ("Дата транзакции", 172, 323), ("цифры номера", 282, 323),
            ("Описание операции", 387, 323), ("Место проведения", 531, 323), ("валюте карт-", 947, 323),
            ("транзакции", 726, 331), ("транзакции", 836, 331), ("счета", 1051, 331),
            ("карточки", 282, 339), ("счета", 947, 339),
        ]
        for (text, x, y) in header { pdf.text(text, x: x, y: y) }

        func row(
            _ y: CGFloat, _ date: String, _ transaction: String, card: String?, description: [String],
            place: String, currency: String = "BYN", amount: String, account: String, balance: String
        ) {
            pdf.text(date, x: 64, y: y)
            pdf.text(transaction, x: 172, y: y)
            if let card { pdf.text(card, x: 282, y: y) }
            // Описание по центру: первая строка над датой, вторая на её уровне, третья ниже.
            let top = y - CGFloat(description.count - 1) / 2 * 15
            for (index, line) in description.enumerated() { pdf.text(line, x: 387, y: top + CGFloat(index) * 15) }
            pdf.text(place, x: 531, y: y)
            pdf.text(currency, x: 726, y: y)
            pdf.text(amount, x: 836, y: y)
            pdf.text(account, x: 947, y: y)
            pdf.text(balance, x: 1051, y: y)
        }

        row(390, "10-10-2026", "09-10-2026", card: "1234", description: ["On-line открытие", "счета"],
            place: "", amount: "0.0", account: "0.0", balance: "0.0")
        row(440, "11-10-2026", "10-10-2026", card: "1234", description: ["Пополнение счета", "Ерип"],
            place: "POPOLNENIE ERIP BSB", amount: "100.0", account: "100.0", balance: "100.0")
        row(490, "12-10-2026", "11-10-2026", card: "1234", description: ["Списание P2P в", "устройствах Банка"],
            place: "PEREVOD BSB", amount: "90.0", account: "90.0", balance: "10.0")
        row(540, "12-10-2026", "11-10-2026", card: "1234", description: ["Отмена списания P2P"],
            place: "PEREVOD BSB", amount: "94.0", account: "90.0", balance: "100.0")
        row(590, "12-10-2026", "11-10-2026", card: "1234", description: ["Плата за Р2Р", "перевод в", "устройствах банка"],
            place: "PEREVOD BSB", amount: "94.0", account: "4.0", balance: "96.0")
        row(650, "13-10-2026", "12-10-2026", card: "1234", description: ["Оплата товаров и", "услуг"],
            place: "SHOP TEST", currency: "USD", amount: "10.0", account: "30.0", balance: "66.0")
        row(700, "31-10-2026", "31-10-2026", card: nil, description: ["Капитализация (%%", "тек.периода ко", "вкладу)"],
            place: "", amount: "0.0", account: "0.0", balance: "66.0")
        row(760, "04-11-2026", "04-11-2026", card: nil, description: ["Корректировка по", "кредиту (без", "проводки)"],
            place: "", amount: "0.0", account: "12.0", balance: "78.0")
        row(810, "04-11-2026", "04-11-2026", card: nil, description: ["Погашение тех", "овердрафта"],
            place: "", amount: "0.0", account: "12.0", balance: "66.0")
        pdf.text("Обороты за период:", x: 1028, y: 860)
        pdf.text("Поступило (+): 202.0", x: 1026, y: 890)
        pdf.text("Списано (-): \(debited)", x: 1042, y: 920)
        pdf.text("07 11 2026", x: 809, y: 1584)
        return pdf
    }

    static func parse(_ pdf: PDFFixture) throws -> ParsedStatement {
        let document = try PDFStatementReader.document(from: pdf.data(), fileName: "bsb.pdf")
        return try BSBBankParser().parse(document)
    }

    private static var minsk: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Minsk")!
        return calendar
    }

    @Test("Знак суммы по изменению остатка, описания с местом, валюта операции")
    func rows() throws {
        let rows = try Self.parse(Self.statement()).rows
        #expect(rows.map(\.amount.minorUnits) == [10_000, -9_000, 9_000, -400, -3_000, 1_200])
        #expect(rows.map(\.description) == [
            "Пополнение счета Ерип POPOLNENIE ERIP BSB",
            "Списание P2P в устройствах Банка PEREVOD BSB",
            "Отмена списания P2P PEREVOD BSB",
            "Плата за Р2Р перевод в устройствах банка PEREVOD BSB",
            "Оплата товаров и услуг SHOP TEST",
            "Корректировка по кредиту (без проводки)",
        ])
        #expect(rows[4].originalAmount == Money(minorUnits: -1_000, currency: .usd))
        #expect(rows[0].originalAmount == nil)
        let day = Self.minsk.dateComponents([.year, .month, .day], from: rows[0].bookedAt)
        #expect(day == DateComponents(year: 2026, month: 10, day: 10))
    }

    @Test("Сводка: карта, валюта, период; обороты сходятся без погашения овердрафта")
    func header() throws {
        let statement = try Self.parse(Self.statement())
        #expect(statement.accountHint == AccountHint(maskedNumber: "1234", currency: .byn))
        #expect(statement.closingBalance == Money(minorUnits: 6_600, currency: .byn))
        let start = try #require(statement.period?.start)
        #expect(Self.minsk.dateComponents([.month, .day], from: start) == DateComponents(month: 10, day: 9))
        #expect(statement.warnings.map(\.message) == [
            "Погашение технического овердрафта — внутренняя проводка банка, пропущено (1)",
        ])
    }

    @Test("Если обороты не сходятся, парсер предупреждает")
    func mismatch() throws {
        let warnings = try Self.parse(Self.statement(debited: "136.0")).warnings.map(\.message)
        #expect(warnings.contains { $0.hasPrefix("Сумма операций не сходится") })
    }

    @Test("Узнаёт свою выписку и не забирает чужие")
    func confidence() throws {
        let own = try PDFStatementReader.document(from: Self.statement().data(), fileName: "a.pdf")
        #expect(BSBBankParser().confidence(for: own) >= 0.7)
        for other in [PriorbankParser(), BelarusbankParser(), AlfabankParser()] as [any StatementParser] {
            #expect(other.confidence(for: own) < 0.3)
        }
        let alfa = try PDFStatementReader.document(from: AlfabankParserTests.statement().data(), fileName: "b.pdf")
        #expect(BSBBankParser().confidence(for: alfa) < 0.3)
    }

    @Test("В списке банков только те, у которых есть парсер")
    func banks() {
        #expect(BankParsersBY.banks.map(\.id) == BankParsersBY.all.map(\.bank.id))
        #expect(BankParsersBY.banks.contains { $0.id == "by.bsb" })
    }
}
