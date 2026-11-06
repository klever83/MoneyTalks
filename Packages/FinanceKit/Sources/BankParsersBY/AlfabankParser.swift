import Domain
import Foundation
import StatementImport

/// Альфа-Банк: «Выписка по операциям, совершенным по банковскому счету» из интернет-банка, PDF (iText).
///
/// Таблица из четырёх колонок: дата, примечание, сумма в валюте счёта, сумма в валюте операции
/// (суммы со знаком и кодом валюты, например `-21.3 BYN`). Примечание многострочное, с рваным
/// правым краем, а дата и суммы выровнены по центру строки, поэтому колонки берутся по шапке,
/// а не по просветам в данных. У карточных операций примечание начинается с даты совершения
/// `ГГГГММДД`; она точнее даты в колонке (это дата отражения по счёту).
public struct AlfabankParser: StatementParser {
    public let id: ParserID = "by.alfabank.pdf"
    public let bank = BankParsersBY.alfabank
    public let formats: Set<StatementFormat> = [.pdf]

    private static let amountHeaderWords: Set<String> = ["Сумма", "в", "валюте", "счета", "операции"]

    public init() {}

    public func confidence(for document: StatementDocument) -> Double {
        guard case let .layout(layout) = document.content else { return 0 }
        let text = layout.text
        var score = 0.0
        if text.contains("\"АЛЬФА-БАНК\"") { score += 0.5 }
        if text.contains(/BY\d{2}ALFA/) { score += 0.3 }
        if text.contains("Выписка по операциям, совершенным по банковскому счету") { score += 0.2 }
        return min(score, 1)
    }

    public func parse(_ document: StatementDocument) throws(ParseError) -> ParsedStatement {
        guard case let .layout(layout) = document.content else { throw .unsupportedFormat }
        let lines = layout.lines

        var accountCurrency: Currency?
        var period: DateInterval?
        var opening: Decimal?
        var closing: Decimal?
        var card: String?
        for line in lines {
            let text = line.text
            if accountCurrency == nil, let match = text.firstMatch(of: /^Валюта счета ([A-Z]{3})/) {
                accountCurrency = Currency(code: String(match.1))
            }
            if period == nil, let match = text.firstMatch(of: /^Период (\d{2}\.\d{2}\.\d{4}) - (\d{2}\.\d{2}\.\d{4})/),
               let start = BYDate.date(String(match.1)), let end = BYDate.date(String(match.2)) {
                period = DateInterval(start: start, end: end.addingTimeInterval(86_399))
            }
            if opening == nil, let match = text.firstMatch(of: /^Баланс на начало периода (-?[\d ]*\d(?:\.\d+)?) [A-Z]{3}/) {
                opening = AmountParser.decimal(from: String(match.1))
            }
            if closing == nil, let match = text.firstMatch(of: /^Баланс на конец периода (-?[\d ]*\d(?:\.\d+)?) [A-Z]{3}/) {
                closing = AmountParser.decimal(from: String(match.1))
            }
            if card == nil, text.hasPrefix("Привязанные карты"), let match = text.firstMatch(of: /\(\d\*+(\d{4})\)/) {
                card = String(match.1)
            }
        }
        guard let accountCurrency else { throw .missingColumn("Валюта счета") }
        guard let boundaries = Self.columnBoundaries(lines) else { throw .missingColumn("Шапка таблицы") }

        let tableLines = TableExtractor.tableLines(
            in: layout,
            isHeader: Self.isHeaderTail,
            isFooter: { $0.text.wholeMatch(of: /\d+ \/ \d+/) != nil }
        )
        let table = TableExtractor.rows(tableLines, boundaries: boundaries) { cells in
            cells[0].wholeMatch(of: /\d{2}\.\d{2}\.\d{4}/) != nil
        }

        var rows: [ParsedRow] = []
        var warnings: [ParseWarning] = []
        for (index, cells) in table.enumerated() {
            guard let postedAt = BYDate.date(cells[0]),
                  let amount = Self.money(cells[2]), amount.currency == accountCurrency
            else {
                warnings.append(ParseWarning(line: nil, message: "Не удалось разобрать операцию №\(index + 1): \(cells.joined(separator: " | "))"))
                continue
            }
            var note = cells[1]
            var bookedAt = postedAt
            // Карточная операция: «20261104 MINSK Покупка товара / …», дата совершения в начале.
            if let match = note.firstMatch(of: /^(\d{4})(\d{2})(\d{2})\s/),
               let date = BYDate.calendar.date(from: DateComponents(year: Int(match.1), month: Int(match.2), day: Int(match.3))),
               abs(date.timeIntervalSince(postedAt)) < 60 * 86_400 {
                bookedAt = date
                note = String(note[match.range.upperBound...])
            }
            var original: Money?
            if let operation = Self.money(cells[3]), operation.currency != accountCurrency {
                original = operation
            }
            rows.append(ParsedRow(bookedAt: bookedAt, amount: amount, originalAmount: original, description: note))
        }

        if layout.uncertainWords > 0 {
            warnings.append(ParseWarning(
                line: nil,
                message: "Положение части текста в PDF определено неточно (\(layout.uncertainWords)): проверьте описания операций"
            ))
        }
        if let opening, let closing {
            let total = rows.reduce(opening) { $0 + $1.amount.decimalValue }
            if total != closing {
                warnings.append(ParseWarning(
                    line: nil,
                    message: "Сумма операций не сходится с балансом выписки: ожидалось \(closing), получилось \(total)"
                ))
            }
        }

        return ParsedStatement(
            accountHint: AccountHint(maskedNumber: card, currency: accountCurrency),
            period: period,
            openingBalance: opening.map { Money($0, currency: accountCurrency) },
            closingBalance: closing.map { Money($0, currency: accountCurrency) },
            rows: rows,
            warnings: warnings
        )
    }

    /// Последняя строка шапки таблицы: только слова заголовков сумм, заканчивается на «операции».
    private static func isHeaderTail(_ line: TextLine) -> Bool {
        line.words.last?.text == "операции" && line.words.allSatisfy { amountHeaderWords.contains($0.text) }
    }

    /// Три границы: дата | примечание | сумма в валюте счёта | сумма в валюте операции.
    /// Суммы стоят под своими заголовками, а примечание кончается левее заголовка суммы в валюте счёта.
    /// Слово относится к колонке по своей середине, поэтому граница — чуть левее начала заголовка.
    private static func columnBoundaries(_ lines: [TextLine]) -> [CGFloat]? {
        guard let headerIndex = lines.firstIndex(where: { line in line.words.contains { $0.text == "Примечание" } }),
              let noteHeader = lines[headerIndex].words.first(where: { $0.text == "Примечание" }),
              let dateHeader = lines[headerIndex].words.first(where: { $0.text == "Дата" })
        else { return nil }

        let block = lines[max(0, headerIndex - 3)...min(lines.count - 1, headerIndex + 3)]
        let amountWords = block
            .flatMap(\.words)
            .filter { $0.frame.minX > noteHeader.frame.maxX && amountHeaderWords.contains($0.text) }
        let amountBoundaries = TableExtractor.columnBoundaries(for: [TextLine(words: amountWords)], minGap: 8)
        guard amountBoundaries.count == 1 else { return nil }
        let split = amountBoundaries[0]
        guard let accountStart = amountWords.filter({ $0.frame.midX < split }).map(\.frame.minX).min(),
              let operationStart = amountWords.filter({ $0.frame.midX > split }).map(\.frame.minX).min()
        else { return nil }

        // Даты в колонке «Дата» выровнены по центру под заголовком; примечание начинается сразу за ними.
        let dateEnd = lines
            .flatMap(\.words)
            .filter { $0.frame.minX < dateHeader.frame.maxX && $0.text.wholeMatch(of: /\d{2}\.\d{2}\.\d{4}/) != nil }
            .map(\.frame.maxX)
            .max() ?? dateHeader.frame.maxX + 12
        return [dateEnd + 2, accountStart - 3, operationStart - 3]
    }

    /// `-21.3 BYN`, `1 250.00 USD`
    private static func money(_ text: String) -> Money? {
        guard let match = text.wholeMatch(of: /(-?[\d ]*\d(?:\.\d+)?) ([A-Z]{3})/),
              let value = AmountParser.decimal(from: String(match.1))
        else { return nil }
        return Money(value, currency: Currency(code: String(match.2)))
    }
}
