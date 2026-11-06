import Domain
import Foundation
import StatementImport

/// Беларусбанк: «Выписка по счету» из мобильного приложения, PDF (iText).
///
/// Таблица из 11 колонок: номер карты, дата и время совершения, дата и время отражения,
/// наименование операции, место, валюта операции, «Приход»/«Расход», сумма в валюте операции,
/// сумма в валюте счёта, остаток после операции, MCC. Ячейки многострочные и выровнены по центру,
/// а текст в PDF записан по колонкам, поэтому таблица собирается по координатам (`TableExtractor`).
/// Границы колонок берутся по шапке таблицы.
public struct BelarusbankParser: StatementParser {
    public let id: ParserID = "by.belarusbank.pdf"
    public let bank = BankParsersBY.belarusbank
    public let formats: Set<StatementFormat> = [.pdf]

    private enum Column: Int, CaseIterable {
        case card, performedAt, postedAt, name, place, currency, direction, amount, accountAmount, balance, mcc
    }

    public init() {}

    public func confidence(for document: StatementDocument) -> Double {
        guard case let .layout(layout) = document.content else { return 0 }
        let text = layout.text
        var score = 0.0
        // BIC Беларусбанка AKBBBY2X входит в IBAN счёта.
        if text.contains(/IBAN: BY\d{2}AKBB/) { score += 0.6 }
        if text.contains("Регистрационный номер приложения") { score += 0.2 }
        if text.contains("Выписка по счету") { score += 0.1 }
        if text.contains("МСС") { score += 0.1 }
        return min(score, 1)
    }

    public func parse(_ document: StatementDocument) throws(ParseError) -> ParsedStatement {
        guard case let .layout(layout) = document.content else { throw .unsupportedFormat }
        let lines = layout.lines

        var accountCurrency: Currency?
        var period: DateInterval?
        var opening: Decimal?
        var closing: Decimal?
        for line in lines {
            let text = line.text
            if let match = text.firstMatch(of: /^Валюта счета: ([A-Z]{3})/) {
                accountCurrency = Currency(code: String(match.1))
            }
            if let match = text.firstMatch(of: /за период (\d{2}\.\d{2}\.\d{4}) - (\d{2}\.\d{2}\.\d{4})/),
               let start = BYDate.date(String(match.1)), let end = BYDate.date(String(match.2)) {
                period = DateInterval(start: start, end: end.addingTimeInterval(86_399))
            }
            if let match = text.firstMatch(of: /^Остаток на начало периода: (-?[\d ]+\.\d{2})/) {
                opening = AmountParser.decimal(from: String(match.1))
            }
            if let match = text.firstMatch(of: /^Остаток на конец периода: (-?[\d ]+\.\d{2})/) {
                closing = AmountParser.decimal(from: String(match.1))
            }
        }
        guard let accountCurrency else { throw .missingColumn("Валюта счета") }

        // Шапка таблицы: от строки «Дата» до строки «по счету». Слова шапки стоят строго
        // в своих колонках, поэтому по ним видно, сколько колонок и где они примерно.
        guard let headerStart = lines.firstIndex(where: { $0.text == "Дата" }),
              let headerEnd = lines[headerStart...].firstIndex(where: { $0.text == "по счету" })
        else { throw .missingColumn("Шапка таблицы") }
        let headerLines = Array(lines[headerStart...headerEnd])
        let headerBoundaries = TableExtractor.columnBoundaries(for: headerLines)
        guard headerBoundaries.count == Column.allCases.count - 1 else { throw .missingColumn("Колонки таблицы") }

        // Колонтитулов и текста после таблицы в выписке нет (проверено на реальных выписках),
        // поэтому таблица идёт от шапки до конца каждой страницы.
        let tableLines = TableExtractor.tableLines(
            in: layout,
            isHeader: { $0.text == "по счету" },
            isFooter: { _ in false }
        )
        // Шапка центрирована и уже данных: длинное «Место» может перейти середину просвета шапки
        // и уехать в «Валюту». Поэтому точные границы — по просветам в данных, если они дают те же
        // колонки, что и шапка (пустая во всей выписке колонка, например, их не даст); иначе по шапке.
        // Порог 3 pt: шире пробела в номере карты (~2 pt), уже самого узкого отступа колонок (~5 pt).
        let fromData = TableExtractor.columnBoundaries(for: tableLines, minGap: 3)
        // Граница из данных должна лежать между соседними границами шапки: тогда колонки те же.
        let sameColumns = fromData.count == headerBoundaries.count && fromData.indices.allSatisfy { index in
            (index == 0 || fromData[index] > headerBoundaries[index - 1])
                && (index == fromData.count - 1 || fromData[index] < headerBoundaries[index + 1])
        }
        let boundaries = sameColumns ? fromData : headerBoundaries
        let table = TableExtractor.rows(tableLines, boundaries: boundaries) { cells in
            cells[Column.performedAt.rawValue].wholeMatch(of: /\d{2}\.\d{2}\.\d{4}.*/) != nil
        }

        var rows: [ParsedRow] = []
        var warnings: [ParseWarning] = []
        var card: String?
        for (index, cells) in table.enumerated() {
            func cell(_ column: Column) -> String { cells[column.rawValue] }
            guard let bookedAt = BYDate.dateTime(cell(.performedAt)),
                  let magnitude = AmountParser.decimal(from: cell(.accountAmount)),
                  cell(.direction) == "Приход" || cell(.direction) == "Расход"
            else {
                warnings.append(ParseWarning(line: nil, message: "Не удалось разобрать операцию №\(index + 1): \(cells.joined(separator: " | "))"))
                continue
            }
            let sign: Decimal = cell(.direction) == "Расход" ? -1 : 1
            if cell(.currency).wholeMatch(of: /[A-Z]{3}/) == nil || cell(.mcc).wholeMatch(of: /\d*/) == nil {
                warnings.append(ParseWarning(
                    line: nil,
                    message: "Операция №\(index + 1): колонки «Валюта»/«МСС» прочитаны неточно, проверьте сумму в валюте операции"
                ))
            }
            var original: Money?
            let currencyCode = cell(.currency)
            if currencyCode.wholeMatch(of: /[A-Z]{3}/) != nil, currencyCode != accountCurrency.code,
               let amount = AmountParser.decimal(from: cell(.amount)) {
                original = Money(sign * abs(amount), currency: Currency(code: currencyCode))
            }
            if card == nil, let match = cell(.card).firstMatch(of: /(\d{4})$/) {
                card = String(match.1)
            }
            let description = [cell(.name), cell(.place)].filter { !$0.isEmpty }.joined(separator: " ")
            rows.append(ParsedRow(
                bookedAt: bookedAt,
                amount: Money(sign * abs(magnitude), currency: accountCurrency),
                originalAmount: original,
                description: description,
                mcc: Int(cell(.mcc))
            ))
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
}
