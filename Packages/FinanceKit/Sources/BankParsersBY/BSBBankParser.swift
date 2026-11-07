import Domain
import Foundation
import StatementImport

/// БСБ Банк: «Выписка по счёту клиента» из интернет-банка, PDF.
///
/// Девять колонок: дата операции, дата транзакции, последние цифры карты, описание, место,
/// валюта транзакции, сумма транзакции, сумма в валюте карт-счёта, остаток. Ячейки выровнены
/// по центру строки, строки идут от старых к новым. Суммы без знака, поэтому направление берётся
/// из остатка относительно предыдущей строки: если он изменился ровно на сумму, знак по нему,
/// иначе по описанию (пополнение, отмена списания и т. п.).
///
/// Остатков на начало и конец периода нет, есть обороты «Поступило» и «Списано»; по ним и сверяемся.
/// «Погашение тех овердрафта» банк в обороты не включает: это внутренняя проводка, которая закрывает
/// технический овердрафт, а деньги со счёта она не списывает. Такая строка пропускается.
public struct BSBBankParser: StatementParser {
    public let id: ParserID = "by.bsb.pdf"
    public let bank = BankParsersBY.bsb
    public let formats: Set<StatementFormat> = [.pdf]

    private static let columnCount = 9
    /// Начала описаний, у которых деньги приходят на счёт.
    private static let creditPrefixes = [
        "пополнение", "отмена", "корректировка по кредиту", "капитализация", "зачисление", "возврат", "поступление",
    ]

    public init() {}

    public func confidence(for document: StatementDocument) -> Double {
        guard case let .layout(layout) = document.content else { return 0 }
        let text = layout.text
        var score = 0.0
        if text.contains("«БСБ Банк»") || text.contains("«БСБ-Банк»") { score += 0.5 }
        if text.contains(/BY\d{2}UNBS/) { score += 0.3 }
        if text.contains("ВЫПИСКА ПО СЧЕТУ КЛИЕНТА") { score += 0.2 }
        return min(score, 1)
    }

    public func parse(_ document: StatementDocument) throws(ParseError) -> ParsedStatement {
        guard case let .layout(layout) = document.content else { throw .unsupportedFormat }
        let lines = layout.lines

        var currency: Currency?
        var period: DateInterval?
        var credited: Decimal?
        var debited: Decimal?
        for line in lines {
            let text = line.text
            if currency == nil, let match = text.firstMatch(of: /^Валюта карт-счета: ([A-Z]{3})/) {
                currency = Currency(code: String(match.1))
            }
            if period == nil, let match = text.firstMatch(of: /с (\d{4}-\d{2}-\d{2}) по (\d{4}-\d{2}-\d{2})/),
               let start = Self.date(String(match.1)), let end = Self.date(String(match.2)) {
                period = DateInterval(start: start, end: end.addingTimeInterval(86_399))
            }
            if credited == nil, let match = text.firstMatch(of: /^Поступило \(\+\): (\d[\d ]*(?:\.\d+)?)/) {
                credited = AmountParser.decimal(from: String(match.1))
            }
            if debited == nil, let match = text.firstMatch(of: /^Списано \(-\): (\d[\d ]*(?:\.\d+)?)/) {
                debited = AmountParser.decimal(from: String(match.1))
            }
        }
        guard let currency else { throw .missingColumn("Валюта карт-счета") }

        guard let headerEnd = lines.firstIndex(where: { line in line.words.contains { $0.text == "карточки" } }),
              let headerStart = lines[..<headerEnd].lastIndex(where: { line in line.words.contains { $0.text == "последние" } })
        else { throw .missingColumn("Шапка таблицы") }
        let boundaries = TableExtractor.columnBoundaries(for: Array(lines[headerStart...headerEnd]), minGap: 6)
        guard boundaries.count == Self.columnCount - 1 else { throw .missingColumn("Шапка таблицы") }

        let tableLines = TableExtractor.tableLines(
            in: layout,
            isHeader: { line in line.words.contains { $0.text == "карточки" } },
            isFooter: { $0.words.first?.text == "Обороты" }
        )
        let table = TableExtractor.rows(tableLines, boundaries: boundaries) { cells in
            cells[0].wholeMatch(of: /\d{2}-\d{2}-\d{4}/) != nil
        }

        var rows: [ParsedRow] = []
        var warnings: [ParseWarning] = []
        /// Сколько операций по каждой карте: у карт-счёта их может быть несколько, для счёта берём основную.
        var cards: [String: Int] = [:]
        var previousBalance: Decimal?
        var lastBalance: Decimal?
        var overdraftRepayments = 0
        for (index, cells) in table.enumerated() {
            guard let bookedAt = Self.date(cells[1]) ?? Self.date(cells[0]),
                  let amount = AmountParser.decimal(from: cells[7]),
                  let balance = AmountParser.decimal(from: cells[8])
            else {
                warnings.append(ParseWarning(line: nil, message: "Не удалось разобрать операцию №\(index + 1): \(cells.joined(separator: " | "))"))
                continue
            }
            defer {
                previousBalance = balance
                lastBalance = balance
            }
            if cells[2].wholeMatch(of: /\d{4}/) != nil { cards[cells[2], default: 0] += 1 }
            guard amount != 0 else { continue }
            let title = cells[3]
            if title.lowercased().hasPrefix("погашение тех") {
                overdraftRepayments += 1
                continue
            }

            let isCredit: Bool
            if let previousBalance, abs(balance - previousBalance) == amount {
                isCredit = balance > previousBalance
            } else {
                isCredit = Self.creditPrefixes.contains { title.lowercased().hasPrefix($0) }
            }
            var original: Money?
            if cells[5].wholeMatch(of: /[A-Z]{3}/) != nil, cells[5] != currency.code,
               let value = AmountParser.decimal(from: cells[6]) {
                original = Money(isCredit ? value : -value, currency: Currency(code: cells[5]))
            }
            rows.append(ParsedRow(
                bookedAt: bookedAt,
                amount: Money(isCredit ? amount : -amount, currency: currency),
                originalAmount: original,
                description: [title, cells[4]].filter { !$0.isEmpty }.joined(separator: " ")
            ))
        }

        if overdraftRepayments > 0 {
            warnings.append(ParseWarning(
                line: nil,
                message: "Погашение технического овердрафта — внутренняя проводка банка, пропущено (\(overdraftRepayments))"
            ))
        }
        if layout.uncertainWords > 0 {
            warnings.append(ParseWarning(
                line: nil,
                message: "Положение части текста в PDF определено неточно (\(layout.uncertainWords)): проверьте описания операций"
            ))
        }
        let income = rows.map(\.amount.decimalValue).filter { $0 > 0 }.reduce(0, +)
        let expense = -rows.map(\.amount.decimalValue).filter { $0 < 0 }.reduce(0, +)
        if let credited, let debited {
            if credited != income || debited != expense {
                warnings.append(ParseWarning(
                    line: nil,
                    message: "Сумма операций не сходится с оборотами выписки: поступило \(credited) и списано \(debited), получилось \(income) и \(expense)"
                ))
            }
        } else {
            warnings.append(BankParsersBY.noCheckWarning)
        }

        let card = cards.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
        let closing = lastBalance
        let opening = closing.map { $0 - income + expense }
        return ParsedStatement(
            accountHint: AccountHint(maskedNumber: card, currency: currency),
            period: period,
            openingBalance: opening.map { Money($0, currency: currency) },
            closingBalance: closing.map { Money($0, currency: currency) },
            rows: rows,
            warnings: warnings
        )
    }

    /// `14-10-2026` или `2026-10-14`
    private static func date(_ text: String) -> Date? {
        if let match = text.wholeMatch(of: /(\d{2})-(\d{2})-(\d{4})/) {
            return BYDate.calendar.date(from: DateComponents(year: Int(match.3), month: Int(match.2), day: Int(match.1)))
        }
        if let match = text.wholeMatch(of: /(\d{4})-(\d{2})-(\d{2})/) {
            return BYDate.calendar.date(from: DateComponents(year: Int(match.1), month: Int(match.2), day: Int(match.3)))
        }
        return nil
    }
}
