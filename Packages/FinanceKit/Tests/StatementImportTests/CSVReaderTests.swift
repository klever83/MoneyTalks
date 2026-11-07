import Domain
import Foundation
import StatementImport
import Testing

@Suite("Чтение CSV")
struct CSVReaderTests {
    @Test("Кавычки, экранирование и CRLF")
    func quotedFields() {
        let text = "Дата;Описание;Сумма\r\n01.11.2026;\"Кафе \"\"Лидо\"\"; Минск\";-12,50\r\n"
        let rows = CSVReader.parse(text)
        #expect(rows == [
            ["Дата", "Описание", "Сумма"],
            ["01.11.2026", "Кафе \"Лидо\"; Минск", "-12,50"],
        ])
    }

    @Test("Определение разделителя", arguments: [
        ("a;b;c", Character(";")),
        ("a,b,c", Character(",")),
        ("a\tb\tc", Character("\t")),
        ("abc", Character(";")),
    ])
    func delimiter(text: String, expected: Character) {
        #expect(CSVReader.detectDelimiter(in: text) == expected)
    }

    @Test("Разделитель по нескольким строкам, а не по первой")
    func delimiterAcrossLines() {
        // В заголовке запятых больше, чем точек с запятой, но в данных стабильна `;`.
        let text = """
        Выписка по счёту, карта, период
        Дата;Описание;Сумма
        01.11.2026;Кафе, Минск;-12,50
        02.11.2026;Такси;-7,00
        03.11.2026;Зарплата;1 500,00
        """
        #expect(CSVReader.detectDelimiter(in: text) == ";")
    }

    @Test("Равенство запятой и табуляции решается порядком кандидатов")
    func delimiterTieIsDeterministic() {
        let text = "a,b\tc\nd,e\tf"
        for _ in 0..<20 {
            #expect(CSVReader.detectDelimiter(in: text) == ",")
        }
    }

    @Test("Windows-1251")
    func cp1251() throws {
        let data = try #require("Сумма;Дата".data(using: .windowsCP1251))
        #expect(CSVReader.decode(data) == "Сумма;Дата")
    }

    @Test("Суммы в разных форматах", arguments: [
        ("1 234,56", "1234.56"),
        ("-12.30", "-12.3"),
        ("1,234.56", "1234.56"),
        ("+15,00", "15"),
        ("1\u{00A0}000", "1000"),
        ("- 11.45", "-11.45"),
        ("\u{2212}5,00", "-5"),
        ("1.234,56", "1234.56"),
    ])
    func amounts(input: String, expected: String) {
        #expect(AmountParser.decimal(from: input) == Decimal(string: expected))
    }

    @Test("Мусор после числа не превращается в сумму", arguments: [
        "1.234.567", "12-30", "12,30 BYN", "abc", "-", "1,234,567", "12..5", "--5",
    ])
    func rejectsPartialMatches(input: String) {
        #expect(AmountParser.decimal(from: input) == nil)
    }

    @Test("Пустая строка не сумма")
    func emptyAmount() {
        #expect(AmountParser.decimal(from: "  ") == nil)
    }
}

@Suite("Дедупликация импорта")
struct DeduplicatorTests {
    let accountID = Account.ID()

    func row(_ minor: Int64, _ text: String = "Кофе", at seconds: TimeInterval = 1_000) -> ParsedRow {
        ParsedRow(
            bookedAt: Date(timeIntervalSince1970: seconds),
            amount: Money(minorUnits: minor, currency: .byn),
            description: text
        )
    }

    @Test("Две одинаковые покупки за день — разные операции")
    func identicalRowsDiffer() {
        let fingerprints = ImportDeduplicator.fingerprints(for: [row(-500), row(-500)], accountID: accountID)
        #expect(Set(fingerprints).count == 2)
    }

    @Test("Повторный импорт той же выписки даёт только дубли")
    func reimport() {
        let rows = [row(-500), row(-500), row(-1200, "Такси")]
        let existing = Set(ImportDeduplicator.fingerprints(for: rows, accountID: accountID))
        let result = ImportDeduplicator.split(rows, accountID: accountID, existing: existing)
        #expect(result.new.isEmpty)
        #expect(result.duplicates.count == 3)
    }

    @Test("Идентификатор банка важнее хэша")
    func bankReference() {
        var withReference = row(-500)
        withReference.bankReference = "TX-42"
        #expect(ImportDeduplicator.fingerprint(for: withReference, accountID: accountID, occurrence: 0) == "ref:TX-42")
    }
}
