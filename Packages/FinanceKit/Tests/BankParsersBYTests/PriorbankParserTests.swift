import BankParsersBY
import Domain
import Foundation
import StatementImport
import Testing

@Suite("Приорбанк")
struct PriorbankParserTests {
    /// Разметка как у «Выписки по контракту» из интернет-банка, данные выдуманные.
    static func statement(currency: String = "BYN") -> PDFFixture {
        var pdf = PDFFixture()
        pdf.text("Выписка по контракту Период выписки 01.10.2026 - 31.10.2026", x: 56, y: 76)
        pdf.text("Номер контракта: …….0001 Валюта контракта \(currency)", x: 56, y: 88)
        pdf.text("Карта: ........4321 VISA GOLD", x: 56, y: 99)
        pdf.text("ФИО: Иван Тестов", x: 56, y: 111)
        pdf.text("Валюта счета: \(currency) Начальный баланс: 1 000.00", x: 56, y: 157)

        func header(_ y: CGFloat) {
            pdf.text("Дата транзакции", x: 64, y: y)
            pdf.text("Операция", x: 276, y: y)
            pdf.text("Сумма", x: 463, y: y)
            pdf.text("Валюта", x: 522, y: y)
            pdf.text("Дата", x: 588, y: y)
            pdf.text("Комиссия/", x: 640, y: y)
            pdf.text("Обороты", x: 700, y: y)
        }
        func row(_ y: CGFloat, _ date: String, _ operation: String, _ amount: String, _ currency: String, _ booked: String, _ turnover: String) {
            pdf.text(date, x: 56, y: y)
            pdf.text(operation, x: 154, y: y)
            pdf.text(amount, x: 487, y: y, .right)
            pdf.text(currency, x: 515, y: y)
            pdf.text(booked, x: 572, y: y)
            pdf.text("0.00", x: 653, y: y, .right)
            pdf.text(turnover, x: 735, y: y, .right)
        }

        pdf.text("Операции по ........0001", x: 56, y: 216)
        header(240)
        row(264, "30.10.2026 00:00:00", "Поступление на контракт клиента 000000-00000-000001", "2 500.00", currency, "30.10.2026", "2 500.00")
        row(276, "30.10.2026 00:00:00", "Payment From Client Contract 000000-00000-000001", "-2 500.00", currency, "30.10.2026", "-2 500.00")
        row(288, "16.10.2026 00:00:00", "Гашение основного долга", "300.00", currency, "16.10.2026", "-300.00")
        pdf.text("Всего по контракту Зачислено Списано Комиссия/Money-back Изменение баланса", x: 56, y: 407)

        pdf.text("Операции по ........4321", x: 56, y: 466)
        header(490)
        row(513, "29.10.2026 14:44:45", "CH Payment BLR MINSK P2P_SDBO", "88.00", currency, "29.10.2026", "88.00")
        pdf.text("https://www.prior.by/web/Cabinet/BankCards/ 01.11.2026 10:00:00", x: 56, y: 537)

        pdf.newPage()
        row(65, "29.10.2026 00:00:00", "Retail BLR MINSK SHOP \"TEST\"", "-12.50", currency, "30.10.2026", "-12.50")
        row(77, "20.10.2026 00:00:00", "Retail KAZ ALMATY YANDEX.GO", "-1 920.00", "KZT", "21.10.2026", "-13.61")
        row(89, "05.10.2026 00:00:00", "Retail BLR MINSK AZS N12", "-1 011.00", currency, "06.10.2026", "-1 011.00")
        pdf.text("Всего в данной валюте Зачислено Списано Комиссия/Money-back Конечный баланс", x: 56, y: 130)
        pdf.text("2 588.00 3 537.11 0.00 50.89", x: 56, y: 142)

        pdf.text("Заблокированные суммы по ........4321", x: 56, y: 200)
        pdf.text("06.11.2026 13:14:38", x: 56, y: 220)
        pdf.text("Retail BLR MINSK", x: 154, y: 220)
        pdf.text("18.00", x: 487, y: 220, .right)
        pdf.text("BYN", x: 515, y: 220)
        pdf.text("KAFE \"TEST\"", x: 154, y: 231)
        return pdf
    }

    private func parse(_ pdf: PDFFixture) throws -> ParsedStatement {
        let document = try PDFStatementReader.document(from: pdf.data(), fileName: "prior.pdf")
        #expect(PriorbankParser().confidence(for: document) >= 0.9)
        return try PriorbankParser().parse(document)
    }

    @Test("Операции, суммы, валюты и шапка выписки")
    func parsesStatement() throws {
        let statement = try parse(Self.statement())
        #expect(statement.accountHint == AccountHint(maskedNumber: "4321", currency: .byn))
        #expect(statement.openingBalance == Money(minorUnits: 100_000, currency: .byn))
        #expect(statement.closingBalance == Money(minorUnits: 5_089, currency: .byn))

        #expect(statement.rows.map(\.amount.minorUnits) == [250_000, -250_000, 8_800, -1_250, -1_361, -101_100])
        #expect(statement.rows.map(\.description) == [
            "Поступление на контракт клиента 000000-00000-000001",
            "Payment From Client Contract 000000-00000-000001",
            "CH Payment BLR MINSK P2P_SDBO",
            "Retail BLR MINSK SHOP \"TEST\"",
            "Retail KAZ ALMATY YANDEX.GO",
            "Retail BLR MINSK AZS N12",
        ])
    }

    @Test("Операция в другой валюте: сумма в валюте счёта и исходная сумма со знаком")
    func foreignCurrency() throws {
        let row = try #require(try parse(Self.statement()).rows.first { $0.description.contains("ALMATY") })
        #expect(row.amount == Money(minorUnits: -1_361, currency: .byn))
        #expect(row.originalAmount == Money(minorUnits: -192_000, currency: Currency(code: "KZT")))
    }

    @Test("Дата и время операции по Минску; 00:00:00 значит, что банк время не дал")
    func dates() throws {
        let rows = try parse(Self.statement()).rows
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Minsk"))
        let p2p = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: rows[2].bookedAt)
        #expect(p2p == DateComponents(year: 2026, month: 10, day: 29, hour: 14, minute: 44, second: 45))
    }

    @Test("Гашение долга и заблокированные суммы не импортируются, баланс сходится")
    func skippedRowsAndBalance() throws {
        let warnings = try parse(Self.statement()).warnings.map(\.message)
        #expect(warnings.contains { $0.hasPrefix("Гашение основного долга") })
        #expect(warnings.contains { $0.hasPrefix("Заблокированные суммы не импортированы (1)") })
        #expect(!warnings.contains { $0.hasPrefix("Сумма операций не сходится") })
    }

    @Test("Если баланс не сходится, парсер предупреждает")
    func balanceMismatch() throws {
        var pdf = Self.statement()
        pdf.text("01.10.2026 00:00:00", x: 56, y: 101)
        pdf.text("Retail BLR MINSK EXTRA", x: 154, y: 101)
        pdf.text("-1.00", x: 487, y: 101, .right)
        pdf.text("BYN", x: 515, y: 101)
        pdf.text("01.10.2026", x: 572, y: 101)
        pdf.text("0.00", x: 653, y: 101, .right)
        pdf.text("-1.00", x: 735, y: 101, .right)
        let warnings = try parse(pdf).warnings.map(\.message)
        #expect(warnings.contains { $0.hasPrefix("Сумма операций не сходится") })
    }

    @Test("Валютный счёт: обороты в валюте счёта")
    func usdAccount() throws {
        let statement = try parse(Self.statement(currency: "USD"))
        #expect(statement.accountHint.currency == .usd)
        let kzt = try #require(statement.rows.first { $0.description.contains("ALMATY") })
        #expect(kzt.amount.currency == .usd)
        #expect(kzt.originalAmount?.currency == Currency(code: "KZT"))
    }

    @Test("Чужие выписки парсер не забирает")
    func lowConfidenceForOthers() throws {
        var pdf = PDFFixture()
        pdf.text("Выписка по счету", x: 20, y: 20)
        pdf.text("07.10.2026 Оплата товаров -5.00 BYN", x: 20, y: 40)
        let document = try PDFStatementReader.document(from: pdf.data(), fileName: "other.pdf")
        #expect(PriorbankParser().confidence(for: document) < 0.5)
    }
}
