import BankParsersBY
import Domain
import Foundation
import StatementImport
import Testing

@Suite("Альфа-Банк")
struct AlfabankParserTests {
    /// Разметка как у выписки по счёту из интернет-банка, данные выдуманные.
    /// Дата и суммы стоят по центру многострочного примечания или на одной из его строк.
    static func statement(closing: String = "85.73") -> PDFFixture {
        var pdf = PDFFixture()
        pdf.pageSize = CGSize(width: 612, height: 792)
        pdf.fontSize = 7
        pdf.text("ОБЩЕСТВО \"АЛЬФА-БАНК\"", x: 455, y: 55)
        pdf.text("Выписка по операциям, совершенным по банковскому счету", x: 42, y: 148)
        pdf.text("Счет BY00ALFA30143000000000000000", x: 52, y: 250)
        pdf.text("Валюта счета BYN", x: 52, y: 270)
        pdf.text("Период 01.10.2026 - 31.10.2026", x: 52, y: 354)
        pdf.text("Баланс на начало периода 100.00 BYN", x: 52, y: 456)
        pdf.text("Баланс на конец периода \(closing) BYN", x: 52, y: 475)
        pdf.text("Привязанные карты Visa Classic(4***********1234)", x: 52, y: 532)

        func header(_ y: CGFloat) -> CGFloat {
            pdf.text("Сумма в", x: 425, y: y)
            pdf.text("Сумма в валюте", x: 489, y: y)
            pdf.text("Дата", x: 54, y: y + 8)
            pdf.text("Примечание", x: 220, y: y + 8)
            pdf.text("валюте счета", x: 415, y: y + 16)
            pdf.text("операции", x: 504, y: y + 16)
            return y + 36
        }
        func amounts(_ y: CGFloat, _ account: String, _ operation: String) {
            pdf.text(account, x: 461, y: y, .right)
            pdf.text(operation, x: 542, y: y, .right)
        }

        var y = header(580)
        // Примечание в три строки, дата и суммы на средней.
        pdf.text("20261004 MINSK Покупка товара / получение услуг SHOP", x: 90, y: y)
        pdf.text("06.10.2026", x: 45, y: y + 8)
        pdf.text("TEST", x: 90, y: y + 8)
        amounts(y + 8, "-25 BYN", "-25 BYN")
        pdf.text("MARKET", x: 90, y: y + 16)
        y += 36
        // Всё в одну строку.
        pdf.text("06.10.2026", x: 45, y: y)
        pdf.text("Зачисление перевода TEST PAYOUT от 05.10.2026", x: 90, y: y)
        amounts(y, "95 BYN", "95 BYN")
        y += 20
        // Дата на первой строке примечания, суммы на второй.
        pdf.text("05.10.2026", x: 45, y: y)
        pdf.text("ИВАН ТЕСТОВ Перевод через АК в рамках одного ФЛ,", x: 90, y: y)
        pdf.text("эл. сообщ. от 05.10.2026", x: 90, y: y + 8)
        amounts(y + 8, "-53.62 BYN", "-53.62 BYN")
        pdf.text("1 / 2", x: 36, y: 752)

        pdf.newPage()
        y = header(43)
        pdf.text("12.10.2026", x: 45, y: y)
        pdf.text("20261010 WARSZAWA Покупка товара / получение услуг SHOP ABROAD", x: 90, y: y)
        amounts(y, "-29.50 BYN", "-10 USD")
        y += 20
        pdf.text("01.10.2026", x: 45, y: y)
        pdf.text("20260930 g MINSK Покупка товара / получение услуг TRANSPORT", x: 90, y: y)
        amounts(y, "-1.15 BYN", "-1.15 BYN")
        pdf.text("2 / 2", x: 36, y: 752)
        return pdf
    }

    static func parse(_ pdf: PDFFixture) throws -> ParsedStatement {
        let document = try PDFStatementReader.document(from: pdf.data(), fileName: "alfa.pdf")
        return try AlfabankParser().parse(document)
    }

    private static var minsk: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Minsk")!
        return calendar
    }

    @Test("Операции и примечания собираются по колонкам шапки, баланс сходится")
    func rows() throws {
        let statement = try Self.parse(Self.statement())
        #expect(statement.rows.map(\.amount.minorUnits) == [-2_500, 9_500, -5_362, -2_950, -115])
        #expect(statement.rows.allSatisfy { $0.amount.currency == .byn })
        #expect(statement.rows.map(\.description) == [
            "MINSK Покупка товара / получение услуг SHOP TEST MARKET",
            "Зачисление перевода TEST PAYOUT от 05.10.2026",
            "ИВАН ТЕСТОВ Перевод через АК в рамках одного ФЛ, эл. сообщ. от 05.10.2026",
            "WARSZAWA Покупка товара / получение услуг SHOP ABROAD",
            "g MINSK Покупка товара / получение услуг TRANSPORT",
        ])
    }

    @Test("Шапка: валюта, карта, период, остатки")
    func header() throws {
        let statement = try Self.parse(Self.statement())
        #expect(statement.accountHint == AccountHint(maskedNumber: "1234", currency: .byn))
        #expect(statement.openingBalance == Money(minorUnits: 10_000, currency: .byn))
        #expect(statement.closingBalance == Money(minorUnits: 8_573, currency: .byn))
        let start = try #require(statement.period?.start)
        #expect(Self.minsk.dateComponents([.year, .month, .day], from: start) == DateComponents(year: 2026, month: 10, day: 1))
    }

    @Test("Дата карточной операции — из примечания, остальных — из колонки")
    func dates() throws {
        let rows = try Self.parse(Self.statement()).rows
        let days = rows.map { Self.minsk.dateComponents([.month, .day], from: $0.bookedAt) }
        #expect(days == [
            DateComponents(month: 10, day: 4),
            DateComponents(month: 10, day: 6),
            DateComponents(month: 10, day: 5),
            DateComponents(month: 10, day: 10),
            DateComponents(month: 9, day: 30),
        ])
    }

    @Test("Операция в другой валюте")
    func originalAmount() throws {
        let rows = try Self.parse(Self.statement()).rows
        #expect(rows[3].originalAmount == Money(minorUnits: -1_000, currency: .usd))
        #expect(rows[0].originalAmount == nil)
    }

    @Test("Если баланс не сходится, парсер предупреждает")
    func balanceMismatch() throws {
        let warnings = try Self.parse(Self.statement(closing: "90.00")).warnings.map(\.message)
        #expect(warnings.contains { $0.hasPrefix("Сумма операций не сходится") })
        let clean = try Self.parse(Self.statement()).warnings
        #expect(clean.isEmpty, "\(clean)")
    }

    @Test("Узнаёт свою выписку и не забирает чужие")
    func confidence() throws {
        let own = try PDFStatementReader.document(from: Self.statement().data(), fileName: "a.pdf")
        #expect(AlfabankParser().confidence(for: own) >= 0.9)
        #expect(PriorbankParser().confidence(for: own) < 0.3)
        #expect(BelarusbankParser().confidence(for: own) < 0.3)
        let prior = try PDFStatementReader.document(from: PriorbankParserTests.statement().data(), fileName: "b.pdf")
        #expect(AlfabankParser().confidence(for: prior) < 0.3)
    }
}
