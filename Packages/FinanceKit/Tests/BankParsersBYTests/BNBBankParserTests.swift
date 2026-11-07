import BankParsersBY
import Domain
import Foundation
import StatementImport
import Testing

@Suite("БНБ-Банк")
struct BNBBankParserTests {
    /// Разметка как у выписки по счёту из интернет-банка, данные выдуманные.
    /// Сводка на первой странице, таблица со второй, шапка повторяется на каждой странице.
    static func statement(opening: String = "50.00", closing: String = "35.87") -> PDFFixture {
        var pdf = PDFFixture()
        pdf.pageSize = CGSize(width: 595, height: 842)
        pdf.fontSize = 7
        pdf.text("ОАО «БНБ-Банк»", x: 445, y: 78)
        pdf.text("Выписка по счёту", x: 54, y: 178)
        pdf.text("Период", x: 54, y: 412)
        pdf.text("01.10.2026 - 31.10.2026", x: 249, y: 412)
        pdf.text("Номер счёта", x: 54, y: 445)
        pdf.text("BY00BLNB30140000000000000000", x: 249, y: 445)
        pdf.text("Валюта счёта", x: 54, y: 497)
        pdf.text("BYN - Белорусский рубль", x: 249, y: 497)
        pdf.text("Информация о картах", x: 54, y: 530)
        pdf.text("5*** **** **** 1234 - Цифровая Mastercard, BYN", x: 249, y: 530)
        pdf.text("Остаток на начало периода", x: 54, y: 657)
        pdf.text("\(opening) BYN", x: 249, y: 657)
        pdf.text("Остаток на конец периода", x: 54, y: 735)
        pdf.text("\(closing) BYN", x: 249, y: 735)
        pdf.text("1/3", x: 538, y: 824)

        func header(_ y: CGFloat) -> CGFloat {
            pdf.text("Дата и время", x: 62, y: y)
            pdf.text("Дата и", x: 132, y: y)
            pdf.text("Сумма в", x: 331, y: y)
            pdf.text("Сумма в", x: 376, y: y)
            pdf.text("Остаток", x: 420, y: y)
            pdf.text("МСС", x: 512, y: y + 5)
            pdf.text("отображения по", x: 56, y: y + 11)
            pdf.text("время", x: 133, y: y + 11)
            pdf.text("Тип операции", x: 185, y: y + 11)
            pdf.text("Описание", x: 269, y: y + 11)
            pdf.text("валюте", x: 333, y: y + 11)
            pdf.text("валюте", x: 378, y: y + 11)
            pdf.text("после", x: 424, y: y + 11)
            pdf.text("Город", x: 468, y: y + 11)
            pdf.text("категория", x: 502, y: y + 16)
            pdf.text("счёту", x: 76, y: y + 21)
            pdf.text("совершения", x: 122, y: y + 21)
            pdf.text("операции", x: 329, y: y + 21)
            pdf.text("счёта", x: 381, y: y + 21)
            pdf.text("операции", x: 417, y: y + 21)
            return y + 40
        }
        /// Строка операции: первая строка ячеек и вторая (продолжения), как в выписке банка.
        func row(
            _ y: CGFloat, shown: String, completed: String, type: [String], details: [String],
            operation: String, account: String, balance: String, city: [String], mcc: String
        ) {
            let shownParts = shown.split(separator: "|").map(String.init)
            let completedParts = completed.split(separator: " ").map(String.init)
            pdf.text(shownParts[0], x: 55, y: y)
            if shownParts.count > 1 { pdf.text(shownParts[1], x: 82, y: y + 10) }
            pdf.text(completedParts[0], x: 124, y: y)
            pdf.text(completedParts[1], x: 129, y: y + 10)
            for (index, line) in type.enumerated() { pdf.text(line, x: 173, y: y + CGFloat(index) * 10) }
            for (index, line) in details.enumerated() { pdf.text(line, x: 263, y: y + CGFloat(index) * 10) }
            pdf.text(operation, x: 325, y: y)
            pdf.text(account, x: 379, y: y)
            pdf.text("BYN", x: 384, y: y + 10)
            pdf.text(balance, x: 416, y: y)
            for (index, line) in city.enumerated() { pdf.text(line, x: 467, y: y + CGFloat(index) * 10) }
            pdf.text(mcc, x: 513, y: y)
        }

        pdf.newPage()
        pdf.text("В выписке отражены как исполненные, так и ещё не обработанные банком операции.", x: 54, y: 48)
        var y = header(129)
        row(y, shown: "07.10.2026 13:52:|36", completed: "05.10.2026 10:36:23", type: ["Безналичная оплата"],
            details: ["SHOP TEST"], operation: "- 11.45 BYN", account: "- 11.45", balance: "38.55 BYN",
            city: ["BLR G.", "MINSK"], mcc: "5411")
        y += 30
        row(y, shown: "07.10.2026 14:08:|09", completed: "07.10.2026 11:43:54", type: ["Зачисление на счет"],
            details: ["BNB-BANK ERIP", "OTHER"], operation: "100.00 BYN", account: "100.00", balance: "138.55 BYN",
            city: ["BLR SOA", "BNB"], mcc: "6012")
        y += 30
        row(y, shown: "08.10.2026 13:53:|39", completed: "06.10.2026 20:11:19", type: ["Безналичная оплата"],
            details: ["APTEKA", "TESTFARM"], operation: "- 108.74", account: "- 108.74", balance: "29.81 BYN",
            city: ["BLR MINSK"], mcc: "5912")
        pdf.text("BYN", x: 339, y: y + 10)
        pdf.text("2/3", x: 538, y: 826)

        pdf.newPage()
        y = header(50)
        row(y, shown: "06.10.2026 10:13:|44", completed: "06.10.2026 10:13:44",
            type: ["Комиссионное", "вознаграждение", "(money-back)"], details: ["-"],
            operation: "0.00 BYN", account: "10.47", balance: "40.28 BYN", city: ["-"], mcc: "-")
        y += 40
        row(y, shown: "30.10.2026 09:21:|47", completed: "30.10.2026 09:21:47", type: ["Капитализация по вкладу"],
            details: ["-"], operation: "0.00 BYN", account: "0.00", balance: "40.28 BYN", city: ["-"], mcc: "-")
        y += 30
        row(y, shown: "В обработке", completed: "31.10.2026 15:14:50", type: ["Безналичная оплата"],
            details: ["SHOP TEST"], operation: "- 4.41 BYN", account: "- 4.41", balance: "35.87 BYN",
            city: ["G. MINSK,", "BLR"], mcc: "5411")
        pdf.text("3/3", x: 538, y: 826)
        return pdf
    }

    static func parse(_ pdf: PDFFixture) throws -> ParsedStatement {
        let document = try PDFStatementReader.document(from: pdf.data(), fileName: "bnb.pdf")
        return try BNBBankParser().parse(document)
    }

    private static var minsk: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Minsk")!
        return calendar
    }

    @Test("Операции со всех страниц таблицы: суммы, описания, MCC")
    func rows() throws {
        let rows = try Self.parse(Self.statement()).rows
        #expect(rows.map(\.amount.minorUnits) == [-1_145, 10_000, -10_874, 1_047])
        #expect(rows.allSatisfy { $0.amount.currency == .byn && $0.originalAmount == nil })
        #expect(rows.map(\.description) == [
            "SHOP TEST",
            "Зачисление на счет BNB-BANK ERIP OTHER",
            "APTEKA TESTFARM",
            "Комиссионное вознаграждение (money-back)",
        ])
        #expect(rows.map(\.mcc) == [5411, 6012, 5912, nil])
    }

    @Test("Дата операции — время совершения, а не отображения по счёту")
    func dates() throws {
        let first = try #require(try Self.parse(Self.statement()).rows.first)
        let components = Self.minsk.dateComponents([.year, .month, .day, .hour, .minute, .second], from: first.bookedAt)
        #expect(components == DateComponents(year: 2026, month: 10, day: 5, hour: 10, minute: 36, second: 23))
    }

    @Test("Сводка: валюта, карта, период, остатки")
    func header() throws {
        let statement = try Self.parse(Self.statement())
        #expect(statement.accountHint == AccountHint(maskedNumber: "1234", currency: .byn))
        #expect(statement.openingBalance == Money(minorUnits: 5_000, currency: .byn))
        #expect(statement.closingBalance == Money(minorUnits: 3_587, currency: .byn))
        let start = try #require(statement.period?.start)
        #expect(Self.minsk.dateComponents([.year, .month, .day], from: start) == DateComponents(year: 2026, month: 10, day: 1))
    }

    @Test("Операции в обработке не импортируются, но входят в сверку с остатком")
    func pending() throws {
        let statement = try Self.parse(Self.statement())
        #expect(!statement.rows.contains { $0.amount.minorUnits == -441 })
        #expect(statement.warnings.map(\.message) == [
            "Операции в обработке не импортированы (1): они появятся после проведения. Следующую выписку выгрузите начиная с 31.10.2026",
        ])
    }

    @Test("Отрицательный остаток со знаком через пробел читается, сверка выполняется")
    func negativeBalance() throws {
        let statement = try Self.parse(Self.statement(opening: "- 14.13", closing: "- 28.26"))
        #expect(statement.openingBalance == Money(minorUnits: -1_413, currency: .byn))
        #expect(statement.closingBalance == Money(minorUnits: -2_826, currency: .byn))
        #expect(!statement.warnings.contains { $0.message.hasPrefix("Сумма операций не сходится") || $0.message.contains("сверка не выполнена") })
    }

    @Test("Если остаток не сходится, парсер предупреждает")
    func balanceMismatch() throws {
        let warnings = try Self.parse(Self.statement(closing: "40.28")).warnings.map(\.message)
        #expect(warnings.contains { $0.hasPrefix("Сумма операций не сходится") })
    }

    @Test("Узнаёт свою выписку и не забирает чужие")
    func confidence() throws {
        let own = try PDFStatementReader.document(from: Self.statement().data(), fileName: "a.pdf")
        #expect(BNBBankParser().confidence(for: own) >= 0.9)
        #expect(PriorbankParser().confidence(for: own) < 0.3)
        #expect(BelarusbankParser().confidence(for: own) < 0.3)
        #expect(AlfabankParser().confidence(for: own) < 0.3)
        let alfa = try PDFStatementReader.document(from: AlfabankParserTests.statement().data(), fileName: "b.pdf")
        #expect(BNBBankParser().confidence(for: alfa) < 0.3)
    }

    @Test("В списке банков только те, у которых есть парсер")
    func banks() {
        #expect(BankParsersBY.banks.map(\.id) == BankParsersBY.all.map(\.bank.id))
        #expect(BankParsersBY.banks.contains { $0.id == "by.bnb" })
    }
}
