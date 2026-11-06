import BankParsersBY
import Domain
import Foundation
import StatementImport
import Testing

@Suite("Беларусбанк")
struct BelarusbankParserTests {
    struct Row {
        var performed: (date: String, time: String)
        var posted: (date: String, time: String)
        var card: String = "1234 56** **** 4321"
        var name: [String] = ["Оплата товаров и услуг"]
        var place: [String] = ["SHOP TEST", "MINSK"]
        var currency = "BYN"
        var direction = "Расход"
        var amount: String
        var accountAmount: String
        var balance: String
        var mcc = "5411"
    }

    /// Разметка как у «Выписки по счету» из мобильного приложения, данные выдуманные.
    /// Ячейки выровнены по центру строки: дата сверху, время снизу, остальное посередине.
    static func statement(rows: [Row], pageBreakAfter: Int? = nil, opening: String = "500.00", closing: String) -> PDFFixture {
        var pdf = PDFFixture()
        pdf.pageSize = CGSize(width: 595, height: 842)
        pdf.fontSize = 6
        pdf.text("Выписка по счету", x: 12, y: 100)
        pdf.text("за период 01.10.2026 - 31.10.2026", x: 12, y: 120)
        pdf.text("Регистрационный номер приложения: 0000001", x: 12, y: 140)
        pdf.text("ФИО владельца счета: Иван Тестов", x: 12, y: 160)
        pdf.text("IBAN: BY00AKBB30140000000000000000", x: 12, y: 180)
        pdf.text("Валюта счета: BYN", x: 12, y: 200)
        pdf.text("Остаток на начало периода: \(opening)", x: 12, y: 220)
        pdf.text("Остаток на конец периода: \(closing)", x: 12, y: 240)
        pdf.text("Дата последней операции по счету: 30.10.2026", x: 12, y: 260)

        func header(_ y: CGFloat) -> CGFloat {
            pdf.text("Дата", x: 148, y: y)
            pdf.text("Дата", x: 100, y: y + 6)
            pdf.text("и время", x: 143, y: y + 12)
            pdf.text("Место", x: 318, y: y + 12)
            pdf.text("Валюта", x: 365, y: y + 12)
            pdf.text("Сумма в", x: 437, y: y + 12)
            pdf.text("Сумма в", x: 481, y: y + 12)
            pdf.text("Остаток", x: 525, y: y + 12)
            pdf.text("и время", x: 96, y: y + 18)
            pdf.text("Приход/", x: 399, y: y + 18)
            pdf.text("Номер карты", x: 22, y: y + 24)
            pdf.text("отражения", x: 137, y: y + 24)
            pdf.text("Наименование операции", x: 192, y: y + 24)
            pdf.text("совершения", x: 307, y: y + 24)
            pdf.text("опера-", x: 367, y: y + 24)
            pdf.text("валюте", x: 439, y: y + 24)
            pdf.text("валюте", x: 483, y: y + 24)
            pdf.text("после", x: 529, y: y + 24)
            pdf.text("МСС", x: 564, y: y + 24)
            pdf.text("совершения", x: 86, y: y + 30)
            pdf.text("Расход", x: 400, y: y + 30)
            pdf.text("операции", x: 139, y: y + 36)
            pdf.text("операции", x: 312, y: y + 36)
            pdf.text("ции", x: 373, y: y + 36)
            pdf.text("операции", x: 435, y: y + 36)
            pdf.text("счета", x: 486, y: y + 36)
            pdf.text("операции", x: 522, y: y + 36)
            pdf.text("операции", x: 91, y: y + 42)
            pdf.text("по счету", x: 141, y: y + 48)
            return y + 64
        }

        var y = header(290)
        for (index, row) in rows.enumerated() {
            // Многострочные ячейки центрированы относительно средней строки `middle`.
            let middle = y + 6
            pdf.text(row.performed.date, x: 89, y: middle - 6)
            pdf.text(row.performed.time, x: 99, y: middle + 6)
            pdf.text(row.posted.date, x: 137, y: middle - 6)
            pdf.text(row.posted.time, x: 147, y: middle + 6)
            if !row.card.isEmpty { pdf.text(row.card, x: 12, y: middle) }
            for (offset, text) in row.name.enumerated() {
                pdf.text(text, x: 181, y: middle + CGFloat(offset * 2 - row.name.count + 1) * 3)
            }
            for (offset, text) in row.place.enumerated() {
                pdf.text(text, x: 300, y: middle + CGFloat(offset * 2 - row.place.count + 1) * 3)
            }
            pdf.text(row.currency, x: 371, y: middle)
            pdf.text(row.direction, x: 400, y: middle)
            pdf.text(row.amount, x: 470, y: middle, .right)
            pdf.text(row.accountAmount, x: 512, y: middle, .right)
            pdf.text(row.balance, x: 556, y: middle, .right)
            pdf.text(row.mcc, x: 564, y: middle)
            y += 30
            if index == pageBreakAfter {
                pdf.newPage()
                y = header(30)
            }
        }
        return pdf
    }

    static let rows: [Row] = [
        Row(performed: ("01.10.2026", "11:43"), posted: ("02.10.2026", "07:06"),
            place: ["ERIP/ BLR", "MINSK"], amount: "100.00", accountAmount: "100.00", balance: "400.00", mcc: "4900"),
        Row(performed: ("03.10.2026", "10:44"), posted: ("03.10.2026", "10:44"), card: "",
            name: ["Зачисление зарплаты", "Тестовая организация"], place: [],
            direction: "Приход", amount: "0.00", accountAmount: "1 595.01", balance: "1 995.01", mcc: ""),
        Row(performed: ("05.10.2026", "12:46"), posted: ("07.10.2026", "05:59"),
            name: ["Выдача наличных"], place: ["ATM TEST", "BLR MINSK"],
            amount: "1 345.00", accountAmount: "1 345.00", balance: "650.01", mcc: "6011"),
        Row(performed: ("10.10.2026", "20:24"), posted: ("12.10.2026", "06:09"),
            name: ["Оплата товаров и услуг"], place: ["SHOP ABROAD", "WARSZAWA"],
            currency: "USD", amount: "10.00", accountAmount: "29.50", balance: "620.51", mcc: "5411"),
    ]

    static func parse(_ pdf: PDFFixture) throws -> ParsedStatement {
        let document = try PDFStatementReader.document(from: pdf.data(), fileName: "statement.pdf")
        return try BelarusbankParser().parse(document)
    }

    @Test("Операции, суммы и подписи по колонкам")
    func rows() throws {
        let statement = try Self.parse(Self.statement(rows: Self.rows, closing: "620.51"))
        #expect(statement.rows.map(\.amount.minorUnits) == [-10000, 159501, -134500, -2950])
        #expect(statement.rows.allSatisfy { $0.amount.currency == .byn })
        #expect(statement.rows.map(\.description) == [
            "Оплата товаров и услуг ERIP/ BLR MINSK",
            "Зачисление зарплаты Тестовая организация",
            "Выдача наличных ATM TEST BLR MINSK",
            "Оплата товаров и услуг SHOP ABROAD WARSZAWA",
        ])
        #expect(statement.rows.map(\.mcc) == [4900, nil, 6011, 5411])
        #expect(statement.warnings.isEmpty, "\(statement.warnings)")
    }

    @Test("Шапка: валюта, карта, период, остатки")
    func header() throws {
        let statement = try Self.parse(Self.statement(rows: Self.rows, closing: "620.51"))
        #expect(statement.accountHint.currency == .byn)
        #expect(statement.accountHint.maskedNumber == "4321")
        #expect(statement.openingBalance?.minorUnits == 50000)
        #expect(statement.closingBalance?.minorUnits == 62051)
        let start = try #require(statement.period?.start)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Minsk"))
        #expect(calendar.dateComponents([.year, .month, .day], from: start) == DateComponents(year: 2026, month: 10, day: 1))
    }

    @Test("Время совершения операции, а не отражения")
    func bookedAt() throws {
        let statement = try Self.parse(Self.statement(rows: Self.rows, closing: "620.51"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Minsk"))
        let first = try #require(statement.rows.first)
        #expect(calendar.dateComponents([.month, .day, .hour, .minute], from: first.bookedAt)
            == DateComponents(month: 10, day: 1, hour: 11, minute: 43))
    }

    @Test("Сумма в валюте операции")
    func originalAmount() throws {
        let statement = try Self.parse(Self.statement(rows: Self.rows, closing: "620.51"))
        #expect(statement.rows[3].originalAmount == Money(Decimal(string: "-10.00")!, currency: Currency(code: "USD")))
        #expect(statement.rows[0].originalAmount == nil)
        #expect(statement.rows[1].originalAmount == nil)
    }

    @Test("Таблица на двух страницах, шапка повторяется")
    func twoPages() throws {
        let statement = try Self.parse(Self.statement(rows: Self.rows, pageBreakAfter: 1, closing: "620.51"))
        #expect(statement.rows.map(\.amount.minorUnits) == [-10000, 159501, -134500, -2950])
        #expect(statement.rows[2].description == "Выдача наличных ATM TEST BLR MINSK")
        #expect(statement.warnings.isEmpty, "\(statement.warnings)")
    }

    @Test("Остаток не сходится — предупреждение")
    func balanceMismatch() throws {
        let statement = try Self.parse(Self.statement(rows: Self.rows, closing: "700.00"))
        #expect(statement.rows.count == 4)
        #expect(statement.warnings.contains { $0.message.contains("не сходится") })
    }

    @Test("Уверенно узнаёт свою выписку и не узнаёт чужую")
    func confidence() throws {
        let own = try PDFStatementReader.document(from: Self.statement(rows: Self.rows, closing: "620.51").data(), fileName: "a.pdf")
        #expect(BelarusbankParser().confidence(for: own) >= 0.9)
        let prior = try PDFStatementReader.document(from: PriorbankParserTests.statement().data(), fileName: "b.pdf")
        #expect(BelarusbankParser().confidence(for: prior) < 0.3)
        #expect(PriorbankParser().confidence(for: own) < 0.3)
    }
}
