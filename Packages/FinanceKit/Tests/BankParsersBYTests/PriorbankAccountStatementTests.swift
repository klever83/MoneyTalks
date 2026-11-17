import BankParsersBY
import Domain
import Foundation
import StatementImport
import Testing

@Suite("Приорбанк: выписка по счёту")
struct PriorbankAccountStatementTests {
    /// Строка таблицы: ячейки выровнены по верху, перенесённые строки идут ниже с шагом 8.
    struct Row {
        var date: String
        var document: [String] = []
        var kind: [String]
        var details: [String] = []
        var place: [String] = []
        var debit = "0.00"
        var credit = "0.00"
        var balance: String
    }

    static let step: CGFloat = 8

    static func draw(_ row: Row, at y: CGFloat, in pdf: inout PDFFixture) {
        pdf.text(row.date, x: 45, y: y)
        for (index, text) in row.document.enumerated() { pdf.text(text, x: 94, y: y + step * CGFloat(index)) }
        for (index, text) in row.kind.enumerated() { pdf.text(text, x: 123, y: y + step * CGFloat(index)) }
        for (index, text) in row.details.enumerated() { pdf.text(text, x: 210, y: y + step * CGFloat(index)) }
        for (index, text) in row.place.enumerated() { pdf.text(text, x: 304, y: y + step * CGFloat(index)) }
        pdf.text(row.debit, x: 431, y: y, .right)
        pdf.text(row.credit, x: 495, y: y, .right)
        pdf.text(row.balance, x: 558, y: y, .right)
        pdf.text("PJCB", x: 572, y: y)
        pdf.text("BY00PJCB0000", x: 626, y: y)
        pdf.text("BBY2", x: 572, y: y + step)
        pdf.text("0000000000000933", x: 620, y: y + step)
    }

    /// Разметка как у «Выписки по счету» Приорбанка, данные выдуманные. Последняя операция первой
    /// страницы продолжается на второй. `repaid: false` — технический овердрафт не погашен до конца периода.
    static func statement(repaid: Bool = true, totals: String? = nil) -> PDFFixture {
        var pdf = PDFFixture()
        pdf.pageSize = CGSize(width: 792, height: 612)
        pdf.fontSize = 6
        pdf.text("'ПРИОРБАНК' ОАО", x: 47, y: 30)
        pdf.text("Приорбанк ОАО Центральный офис", x: 47, y: 38)
        pdf.text("БИК PJCBBY2X", x: 47, y: 46)
        pdf.text("Клиент Иван Тестов", x: 47, y: 54)
        pdf.text("Тип договора 81 - Договор текущего(расчетного) банковского счета в BYN с использованием карточки", x: 47, y: 62)
        pdf.text("Договор № 0000001 от 01.01.2020", x: 47, y: 70)
        pdf.text("Номер счета в формате IBAN: BY00PJCB30140000081001234933", x: 47, y: 78)
        pdf.text("Код валюты - 933 (Белорусский рубль)", x: 47, y: 86)
        pdf.text("Выписка по счету с 06.11.2024 по 06.12.2024", x: 47, y: 94)
        pdf.text("Дата последней операции 06.12.2024", x: 47, y: 102)

        pdf.text("Дата", x: 55, y: 200)
        pdf.text("№", x: 94, y: 200)
        pdf.text("Вид операции", x: 138, y: 200)
        pdf.text("Детализация", x: 228, y: 200)
        pdf.text("Место", x: 326, y: 200)
        pdf.text("Обороты", x: 423, y: 200)
        pdf.text("Остаток", x: 515, y: 200)
        pdf.text("Корреспондент", x: 605, y: 200)
        pdf.text("Код", x: 716, y: 200)
        pdf.text("операции", x: 47, y: 209)
        pdf.text("док", x: 94, y: 209)
        pdf.text("oперации", x: 235, y: 209)
        pdf.text("проведения", x: 316, y: 209)
        pdf.text("платежа", x: 708, y: 209)
        pdf.text("Списание", x: 390, y: 218)
        pdf.text("Поступление", x: 445, y: 218)
        pdf.text("Банк", x: 572, y: 218)
        pdf.text("Счет", x: 644, y: 218)
        pdf.text("oперации", x: 320, y: 227)
        pdf.text("в бюджет", x: 708, y: 227)

        pdf.text("Входящий остаток", x: 47, y: 238)
        pdf.text("0.00", x: 431, y: 238, .right)
        pdf.text("2,016.25", x: 495, y: 238, .right)

        let bank = ["Приорбанк ОАО", "Центральный офис"]
        var rows = [
            Row(date: "06.11.2024", document: ["310"], kind: ["Списание по реестру", "карт-центра (-)"],
                details: ["МАГАЗИН"], place: ["BLR, MINSK"], debit: "44.10", balance: "1,972.15"),
            Row(date: "15.11.2024", document: ["320"], kind: ["Зачисление по реестру", "карт-центра (+)"],
                details: ["ПЕРЕВОД"], place: [","], credit: "50.00", balance: "2,022.15"),
            Row(date: "15.11.2024", kind: ["Зачисление по", "ведомости (+)"],
                details: ["Зачисление согласно ПП", "N123 от 15.11.2024.", "Плательщик", "ООО ТЕСТ", "УНП 100000000"],
                place: bank, credit: "1,000.00", balance: "3,022.15"),
            Row(date: "29.11.2024", document: ["1"], kind: ["Уплата процентов (+)"], place: bank, credit: "3.50", balance: "3,025.65"),
            Row(date: "01.12.2024", document: ["1234", "5"], kind: ["Зачисление с", "транзитного счёта", "(пополнение счета) (+)"],
                place: bank, credit: "450.00", balance: "3,475.65"),
            Row(date: "02.12.2024", document: ["141"], kind: ["Списание по реестру", "карт-центра (-)"],
                details: ["МАГАЗИН ЕДА", "ФИЛИАЛ 2"], place: ["BLR, ГОРОД"], debit: "3,500.00", balance: "-24.35"),
            Row(date: "02.12.2024", document: ["125"], kind: ["Учет технического", "овердрафта (+)"],
                place: bank, credit: "24.35", balance: "0.00"),
            Row(date: "03.12.2024", document: ["330"], kind: ["Зачисление по реестру", "карт-центра (+)"],
                details: ["ПЕРЕВОД"], place: [","], credit: "100.00", balance: "100.00"),
        ]
        if repaid {
            rows.append(Row(date: "03.12.2024", document: ["126"], kind: ["Погашение технического", "овердрафта (-)"],
                            place: bank, debit: "24.35", balance: "75.65"))
        }
        var y: CGFloat = 250
        for (index, row) in rows.enumerated() {
            draw(row, at: y, in: &pdf)
            // Вторая часть детализации у карточной операции стоит отдельным куском в той же строке.
            if index == 5 { pdf.text("M", x: 280, y: y) }
            y += step * CGFloat(max(row.kind.count, row.details.count, row.place.count, row.document.count, 2)) + 2
        }

        // Перевод начинается внизу первой страницы и продолжается на второй.
        draw(Row(date: "05.12.2024", document: ["1579"], kind: ["Перевод с продажей"], place: ["Приорбанк ОАО ПРК"],
                 debit: "50.00", balance: repaid ? "25.65" : "50.00"), at: 590, in: &pdf)
        pdf.newPage()
        pdf.text("валюты по списку", x: 123, y: 30)
        pdf.text("ДОРЦ", x: 326, y: 30)
        pdf.text("ПДПП между счетами", x: 123, y: 38)
        pdf.text("клиента (-)", x: 123, y: 46)
        draw(Row(date: "06.12.2024", document: ["340"], kind: ["Списание по реестру", "карт-центра (-)"],
                 details: ["АПТЕКА"], place: ["BLR, MINSK"], debit: "5.00", balance: repaid ? "20.65" : "45.00"), at: 60, in: &pdf)

        pdf.text("Итого оборотов", x: 47, y: 90)
        let sums = totals ?? (repaid ? "3,623.45 1,627.85" : "3,599.10 1,627.85")
        let parts = sums.split(separator: " ").map(String.init)
        pdf.text(parts[0], x: 431, y: 90, .right)
        pdf.text(parts[1], x: 495, y: 90, .right)
        pdf.text("Исходящий остаток", x: 47, y: 98)
        pdf.text("0.00", x: 431, y: 98, .right)
        pdf.text(repaid ? "20.65" : "45.00", x: 495, y: 98, .right)
        pdf.text("Оператор ____ 000 - Тестова А.", x: 47, y: 130)
        return pdf
    }

    private func document(_ pdf: PDFFixture) throws -> StatementDocument {
        try PDFStatementReader.document(from: pdf.data(), fileName: "prior-account.pdf")
    }

    private func parse(_ pdf: PDFFixture) throws -> ParsedStatement {
        let document = try document(pdf)
        #expect(PriorbankParser().confidence(for: document) >= 0.9)
        return try PriorbankParser().parse(document)
    }

    @Test("Выписка по счёту определяется как Приорбанк, а не Беларусбанк")
    func detection() throws {
        let document = try document(Self.statement())
        let parser = ParserRegistry(parsers: BankParsersBY.all).bestMatch(for: document)
        #expect(parser?.id == PriorbankParser().id)
        #expect(BelarusbankParser().confidence(for: document) < 0.5)
    }

    @Test("Операции, суммы, описания и шапка")
    func parsesStatement() throws {
        let statement = try parse(Self.statement())
        #expect(statement.accountHint.currency == .byn)
        // Код валюты на конце IBAN в маску не входит: это последние цифры номера договора.
        #expect(statement.accountHint.maskedNumber == "1234")
        #expect(statement.openingBalance == Money(minorUnits: 201_625, currency: .byn))
        #expect(statement.closingBalance == Money(minorUnits: 2_065, currency: .byn))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Minsk"))
        let period = try #require(statement.period)
        #expect(calendar.dateComponents([.year, .month, .day], from: period.start) == DateComponents(year: 2024, month: 11, day: 6))
        #expect(calendar.dateComponents([.year, .month, .day], from: period.end) == DateComponents(year: 2024, month: 12, day: 6))

        #expect(statement.rows.map(\.amount.minorUnits) == [-4_410, 5_000, 100_000, 350, 45_000, -350_000, 10_000, -5_000, -500])
        #expect(statement.rows.map(\.description) == [
            "МАГАЗИН BLR, MINSK",
            "ПЕРЕВОД",
            "Зачисление по ведомости Зачисление согласно ПП N123 от 15.11.2024.",
            "Уплата процентов",
            "Зачисление с транзитного счёта (пополнение счета)",
            "МАГАЗИН ЕДА M ФИЛИАЛ 2 BLR, ГОРОД",
            "ПЕРЕВОД",
            "Перевод с продажей валюты по списку ПДПП между счетами клиента",
            "АПТЕКА BLR, MINSK",
        ])
        let first = try #require(statement.rows.first)
        #expect(calendar.dateComponents([.year, .month, .day, .hour], from: first.bookedAt)
            == DateComponents(year: 2024, month: 11, day: 6, hour: 0))
    }

    @Test("Погашенный технический овердрафт пропускается, обороты и остаток сходятся")
    func overdraftSkipped() throws {
        let warnings = try parse(Self.statement()).warnings.map(\.message)
        #expect(warnings.contains { $0.hasPrefix("Учёт и погашение технического овердрафта") && $0.contains("(2)") })
        #expect(!warnings.contains { $0.hasPrefix("Сумма операций не сходится") })
        #expect(!warnings.contains { $0.hasPrefix("Не удалось разобрать") })
    }

    @Test("Непогашенный овердрафт импортируется, чтобы сошёлся остаток")
    func overdraftOpen() throws {
        let statement = try parse(Self.statement(repaid: false))
        #expect(statement.rows.count == 10)
        #expect(statement.rows.contains { $0.description == "Учет технического овердрафта" })
        let warnings = statement.warnings.map(\.message)
        #expect(warnings.contains { $0.hasPrefix("Технический овердрафт за период не закрыт") })
        #expect(!warnings.contains { $0.hasPrefix("Сумма операций не сходится") })
    }

    @Test("Если обороты не сходятся, парсер предупреждает")
    func totalsMismatch() throws {
        let warnings = try parse(Self.statement(totals: "3,600.00 1,627.85")).warnings.map(\.message)
        #expect(warnings.contains { $0.hasPrefix("Сумма операций не сходится с оборотами") })
    }
}
