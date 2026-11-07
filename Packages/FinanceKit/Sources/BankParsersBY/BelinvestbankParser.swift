import Domain
import Foundation
import StatementImport

/// Белинвестбанк: «Мини-выписка по карточке» из интернет-банка, PDF.
///
/// Таблица из двенадцати колонок, шапка только на первой странице: дата операции, дата обработки,
/// карта, код авторизации, тип, MCC, место, сумма в валюте транзакции, сумма и комиссия в валюте
/// счёта (`-1.15/0.00 BYN`), остаток после операции, статус, номер в ЕРИП. Строки идут от новых
/// к старым, ячейки выровнены по верху. Остатков на начало и конец периода в выписке нет, есть
/// остаток после каждой операции и обороты «Приход» и «Расход»: по ним и сверяемся.
///
/// Заблокированные суммы (статус «ЗАБЛОКИРОВАНО», в валюте счёта `0.00/0.00`) не импортируются,
/// как и у Приорбанка: они придут проведёнными в следующей выписке.
public struct BelinvestbankParser: StatementParser {
    public let id: ParserID = "by.belinvestbank.card.pdf"
    public let bank = BankParsersBY.belinvestbank
    public let formats: Set<StatementFormat> = [.pdf]

    private static let columnCount = 12

    public init() {}

    public func confidence(for document: StatementDocument) -> Double {
        guard case let .layout(layout) = document.content else { return 0 }
        let text = layout.text
        var score = 0.0
        if text.contains("Белинвестбанк") || text.contains("BLBBBY2X") { score += 0.5 }
        if text.contains("Мини-выписка по карточке") { score += 0.5 }
        return min(score, 1)
    }

    public func parse(_ document: StatementDocument) throws(ParseError) -> ParsedStatement {
        guard case let .layout(layout) = document.content else { throw .unsupportedFormat }
        let lines = layout.lines

        var accountCurrency: Currency?
        var period: DateInterval?
        var card: String?
        var income: Decimal?
        var expense: Decimal?
        for line in lines {
            let text = line.text
            if accountCurrency == nil, let match = text.firstMatch(of: /^Валюта счета: ([A-Z]{3})/) {
                accountCurrency = Currency(code: String(match.1))
            }
            if text.hasPrefix("Мини-выписка по карточке") {
                card = text.firstMatch(of: /\*{4} \*{4} \*{4} (\d{4})/).map { String($0.1) }
                if let match = text.firstMatch(of: /с (\d{2}\.\d{2}\.\d{4}) по (\d{2}\.\d{2}\.\d{4})/),
                   let start = BYDate.date(String(match.1)), let end = BYDate.date(String(match.2)) {
                    period = DateInterval(start: start, end: end.addingTimeInterval(86_399))
                }
            }
            if income == nil, let match = text.firstMatch(of: /^Приход: (-?\d+(?:\.\d+)?) [A-Z]{3}/) {
                income = AmountParser.decimal(from: String(match.1))
            }
            if expense == nil, let match = text.firstMatch(of: /^Расход: (-?\d+(?:\.\d+)?) [A-Z]{3}/) {
                expense = AmountParser.decimal(from: String(match.1))
            }
        }
        guard let accountCurrency else { throw .missingColumn("Валюта счета") }
        guard let headerIndex = lines.firstIndex(where: { line in line.words.contains { $0.text == "Карточки" } }) else {
            throw .missingColumn("Шапка таблицы")
        }
        // Шапка в пять строк; кончается перед первой операцией.
        let headerEnd = lines[headerIndex...].firstIndex(where: Self.startsWithDate) ?? lines.endIndex
        let boundaries = TableExtractor.columnBoundaries(for: Array(lines[headerIndex..<headerEnd]), minGap: 5)
        guard boundaries.count == Self.columnCount - 1 else { throw .missingColumn("Шапка таблицы") }

        // На каждой странице таблица начинается с первой операции и идёт до номера страницы или итогов.
        let tableLines = layout.pages.flatMap { page -> [TextLine] in
            guard let start = page.lines.firstIndex(where: Self.startsWithDate) else { return [] }
            let rest = page.lines[start...]
            let end = rest.firstIndex { line in
                line.words.first.map { ["Стр.", "Приход:", "Расход:"].contains($0.text) } ?? false
            } ?? page.lines.endIndex
            return Array(page.lines[start..<end])
        }
        let table = TableExtractor.rows(tableLines, boundaries: boundaries) { cells in
            cells[0].firstMatch(of: /^\d{4}-\d{2}-\d{2}/) != nil
        }

        var rows: [ParsedRow] = []
        var warnings: [ParseWarning] = []
        var blocked = 0
        /// Остаток после операции и её полная сумма (с комиссией), по порядку выписки.
        var chain: [(balance: Decimal, total: Decimal)] = []
        for (index, cells) in table.enumerated() {
            if cells[10].replacingOccurrences(of: " ", with: "").hasPrefix("ЗАБЛОКИРОВ") {
                blocked += 1
                continue
            }
            guard let bookedAt = Self.dateTime(cells[0]),
                  let (amount, fee) = Self.amountAndFee(cells[8], currency: accountCurrency),
                  let balance = Self.decimal(cells[9])
            else {
                warnings.append(ParseWarning(line: nil, message: "Не удалось разобрать операцию №\(index + 1): \(cells.joined(separator: " | "))"))
                continue
            }
            let type = cells[4]
            let place = cells[6]
            let description = type == "Покупка" && !place.isEmpty
                ? place
                : [type, place].filter { !$0.isEmpty }.joined(separator: " ")
            var original: Money?
            if let operation = Self.money(cells[7]), operation.currency != accountCurrency {
                original = operation
            }
            // Код авторизации повторяется со временем, поэтому в паре с моментом операции.
            let reference = cells[3].isEmpty ? nil : "\(Int64(bookedAt.timeIntervalSince1970))/\(cells[3])"
            rows.append(ParsedRow(
                bookedAt: bookedAt,
                amount: Money(amount, currency: accountCurrency),
                originalAmount: original,
                description: description,
                mcc: Int(cells[5]),
                bankReference: reference
            ))
            if fee != 0 {
                rows.append(ParsedRow(
                    bookedAt: bookedAt,
                    amount: Money(-abs(fee), currency: accountCurrency),
                    description: "Комиссия: \(description)",
                    bankReference: reference.map { "\($0)/fee" }
                ))
            }
            chain.append((balance, amount - abs(fee)))
        }

        if blocked > 0 {
            warnings.append(ParseWarning(
                line: nil,
                message: "Заблокированные суммы не импортированы (\(blocked)): они появятся после проведения"
            ))
        }
        // Строки от новых к старым: остаток каждой — остаток следующей (более старой) плюс сумма.
        for (newer, older) in zip(chain, chain.dropFirst()) where newer.balance != older.balance + newer.total {
            warnings.append(ParseWarning(
                line: nil,
                message: "Остаток после операции не сходится: \(older.balance) и \(newer.total) дают не \(newer.balance)"
            ))
            break
        }
        let credited = rows.map(\.amount.decimalValue).filter { $0 > 0 }.reduce(0, +)
        let debited = -rows.map(\.amount.decimalValue).filter { $0 < 0 }.reduce(0, +)
        if let income, let expense, income != credited || expense != debited {
            warnings.append(ParseWarning(
                line: nil,
                message: "Сумма операций не сходится с оборотами выписки: приход \(income) и расход \(expense), получилось \(credited) и \(debited)"
            ))
        }

        let closing = chain.first?.balance
        let opening = chain.last.map { $0.balance - $0.total }
        return ParsedStatement(
            accountHint: AccountHint(maskedNumber: card, currency: accountCurrency),
            period: period,
            openingBalance: opening.map { Money($0, currency: accountCurrency) },
            closingBalance: closing.map { Money($0, currency: accountCurrency) },
            rows: rows,
            warnings: warnings
        )
    }

    private static func startsWithDate(_ line: TextLine) -> Bool {
        line.words.first?.text.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil
    }

    /// `2026-11-04 11:56:29`
    private static func dateTime(_ text: String) -> Date? {
        guard let match = text.wholeMatch(of: /(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/) else { return nil }
        return BYDate.calendar.date(from: DateComponents(
            year: Int(match.1), month: Int(match.2), day: Int(match.3),
            hour: Int(match.4), minute: Int(match.5), second: Int(match.6)
        ))
    }

    /// `-1.15/0.00 BYN`: сумма и комиссия в валюте счёта.
    private static func amountAndFee(_ text: String, currency: Currency) -> (Decimal, Decimal)? {
        guard let match = text.wholeMatch(of: /(-?\d+(?:\.\d+)?)\/(-?\d+(?:\.\d+)?)(?: ([A-Z]{3}))?/),
              match.3.map({ String($0) == currency.code }) ?? true,
              let amount = AmountParser.decimal(from: String(match.1)),
              let fee = AmountParser.decimal(from: String(match.2))
        else { return nil }
        return (amount, fee)
    }

    /// `32.51 BYN` или `24.46`
    private static func decimal(_ text: String) -> Decimal? {
        guard let match = text.wholeMatch(of: /(-?\d+(?:\.\d+)?)(?: [A-Z]{3})?/) else { return nil }
        return AmountParser.decimal(from: String(match.1))
    }

    /// `-1.15 BYN`
    private static func money(_ text: String) -> Money? {
        guard let match = text.wholeMatch(of: /(-?\d+(?:\.\d+)?) ([A-Z]{3})/),
              let value = AmountParser.decimal(from: String(match.1))
        else { return nil }
        return Money(value, currency: Currency(code: String(match.2)))
    }
}
