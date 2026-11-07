import Domain
import Foundation
import StatementImport

/// БНБ-Банк: «Выписка по счёту» из интернет-банка, PDF.
///
/// Первая страница — сводка (период, валюта, карта, остатки и обороты), со второй идёт таблица
/// из девяти колонок, шапка повторяется на каждой странице: дата отображения по счёту, дата и время
/// совершения, тип операции, описание, сумма в валюте операции, сумма в валюте счёта, остаток,
/// город, MCC. Ячейки многострочные и выровнены по верху, суммы со знаком через пробел: `- 11.45 BYN`.
///
/// В выписку попадают и операции, которые банк ещё не обработал («В обработке» вместо даты
/// отображения). Как и заблокированные суммы Приорбанка, они не импортируются: сумма при проведении
/// может измениться, и тогда получился бы дубль. Но остаток на конец периода их уже учитывает,
/// поэтому в сверке с остатком они участвуют.
public struct BNBBankParser: StatementParser {
    public let id: ParserID = "by.bnb.pdf"
    public let bank = BankParsersBY.bnb
    public let formats: Set<StatementFormat> = [.pdf]

    private static let columnCount = 9

    public init() {}

    public func confidence(for document: StatementDocument) -> Double {
        guard case let .layout(layout) = document.content else { return 0 }
        let text = layout.text
        var score = 0.0
        if text.contains("«БНБ-Банк»") { score += 0.5 }
        if text.contains(/BY\d{2}BLNB/) { score += 0.3 }
        if text.contains("Дата и время") && text.contains("отображения по") { score += 0.2 }
        return min(score, 1)
    }

    public func parse(_ document: StatementDocument) throws(ParseError) -> ParsedStatement {
        guard case let .layout(layout) = document.content else { throw .unsupportedFormat }

        var accountCurrency: Currency?
        var period: DateInterval?
        var opening: Decimal?
        var closing: Decimal?
        var card: String?
        for line in layout.lines {
            let text = line.text
            if accountCurrency == nil, let match = text.firstMatch(of: /^Валюта счёта ([A-Z]{3})/) {
                accountCurrency = Currency(code: String(match.1))
            }
            if period == nil, let match = text.firstMatch(of: /^Период (\d{2}\.\d{2}\.\d{4}) - (\d{2}\.\d{2}\.\d{4})/),
               let start = BYDate.date(String(match.1)), let end = BYDate.date(String(match.2)) {
                period = DateInterval(start: start, end: end.addingTimeInterval(86_399))
            }
            // Знак может стоять через пробел, как в таблице: `- 12.00 BYN`.
            if opening == nil, let match = text.firstMatch(of: /^Остаток на начало периода ([+-]?\s?\d[\d ]*(?:\.\d+)?) [A-Z]{3}/) {
                opening = AmountParser.decimal(from: String(match.1))
            }
            if closing == nil, let match = text.firstMatch(of: /^Остаток на конец периода ([+-]?\s?\d[\d ]*(?:\.\d+)?) [A-Z]{3}/) {
                closing = AmountParser.decimal(from: String(match.1))
            }
            if card == nil, let match = text.firstMatch(of: /^Информация о картах \d\*{3} \*{4} \*{4} (\d{4})/) {
                card = String(match.1)
            }
        }
        guard let accountCurrency else { throw .missingColumn("Валюта счёта") }

        // Каждая страница таблицы со своей шапкой: колонки берутся по ней, а данные идут до номера страницы.
        var table: [[String]] = []
        for page in layout.pages {
            guard let header = Self.header(in: page.lines) else { continue }
            let boundaries = TableExtractor.columnBoundaries(for: Array(page.lines[header]), minGap: 4)
            guard boundaries.count == Self.columnCount - 1 else { throw .missingColumn("Шапка таблицы") }
            let body = page.lines[(header.upperBound)...]
            let end = body.firstIndex { $0.text.wholeMatch(of: /\d+\/\d+/) != nil } ?? page.lines.endIndex
            table += TableExtractor.rows(Array(page.lines[header.upperBound..<end]), boundaries: boundaries) { cells in
                cells[1].firstMatch(of: /^\d{2}\.\d{2}\.\d{4}/) != nil
            }
        }

        var rows: [ParsedRow] = []
        var warnings: [ParseWarning] = []
        var pending: [Money] = []
        for (index, cells) in table.enumerated() {
            guard let bookedAt = BYDate.dateTime(cells[1]),
                  let amount = Self.money(cells[5]), amount.currency == accountCurrency
            else {
                warnings.append(ParseWarning(line: nil, message: "Не удалось разобрать операцию №\(index + 1): \(cells.joined(separator: " | "))"))
                continue
            }
            // Начисления по нулям (капитализация без процентов) в выписке есть, но это не операции.
            guard amount.minorUnits != 0 else { continue }
            if cells[0].hasPrefix("В обработке") {
                pending.append(amount)
                continue
            }

            let type = cells[2]
            let details = cells[3] == "-" ? "" : cells[3]
            // У покупки описание — название магазина, у остального (зачисления, списания, ЕРИП) важен и тип.
            let description = type == "Безналичная оплата" && !details.isEmpty
                ? details
                : [type, details].filter { !$0.isEmpty }.joined(separator: " ")
            var original: Money?
            if let operation = Self.money(cells[4]), operation.currency != accountCurrency {
                original = operation
            }
            rows.append(ParsedRow(
                bookedAt: bookedAt,
                amount: amount,
                originalAmount: original,
                description: description,
                mcc: Int(cells[8])
            ))
        }

        if !pending.isEmpty {
            warnings.append(BankParsersBY.pendingWarning("Операции в обработке", count: pending.count, periodEnd: period?.end))
        }
        if layout.uncertainWords > 0 {
            warnings.append(ParseWarning(
                line: nil,
                message: "Положение части текста в PDF определено неточно (\(layout.uncertainWords)): проверьте описания операций"
            ))
        }
        if let opening, let closing {
            let total = rows.map(\.amount).reduce(opening) { $0 + $1.decimalValue }
                + pending.reduce(Decimal(0)) { $0 + $1.decimalValue }
            if total != closing {
                warnings.append(ParseWarning(
                    line: nil,
                    message: "Сумма операций не сходится с остатком выписки: ожидалось \(closing), получилось \(total)"
                ))
            }
        } else {
            warnings.append(BankParsersBY.noCheckWarning)
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

    /// Строки шапки таблицы на странице: от строки с «Остаток» до строки, которая начинается со «счёту».
    private static func header(in lines: [TextLine]) -> Range<Int>? {
        guard let end = lines.firstIndex(where: { $0.words.first?.text == "счёту" && $0.words.contains { $0.text == "совершения" } }),
              let start = lines[..<end].lastIndex(where: { line in line.words.contains { $0.text == "Остаток" } })
        else { return nil }
        return start..<(end + 1)
    }

    /// `- 11.45 BYN`, `100.00 BYN`, `- 1 250.00 USD`
    private static func money(_ text: String) -> Money? {
        let compact = text.filter { !$0.isWhitespace }
        guard let match = compact.wholeMatch(of: /([+-]?\d+(?:\.\d+)?)([A-Z]{3})/),
              let value = AmountParser.decimal(from: String(match.1))
        else { return nil }
        return Money(value, currency: Currency(code: String(match.2)))
    }
}
