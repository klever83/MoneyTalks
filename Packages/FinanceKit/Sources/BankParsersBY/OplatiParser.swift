import Domain
import Foundation
import StatementImport

/// Оплати (электронный кошелёк Белинвестбанка): «Выписка по операциям электронного кошелька», PDF.
///
/// Колонки: дата и время, Id операции, тип платежа, приход, расход, остаток после операции,
/// валюта, детали (контрагент). Просветы между колонками в шапке всего в несколько пунктов,
/// поэтому границы ставятся по началу заголовков: все колонки выровнены по левому краю.
/// У каждой операции есть свой Id, по нему и отсеиваются дубли.
public struct OplatiParser: StatementParser {
    public let id: ParserID = "by.oplati.pdf"
    public let bank = BankParsersBY.oplati
    public let formats: Set<StatementFormat> = [.pdf]

    /// Первое слово заголовка каждой колонки, кроме даты.
    private static let headerStarts = ["Id", "Тип", "Приход", "Расход", "Остаток", "Валюта", "Детали"]

    public init() {}

    public func confidence(for document: StatementDocument) -> Double {
        guard case let .layout(layout) = document.content else { return 0 }
        let text = layout.text
        var score = 0.0
        if text.contains("Выписка по операциям электронного кошелька") { score += 0.6 }
        if text.contains("Белинвестбанк") { score += 0.4 }
        return min(score, 1)
    }

    public func parse(_ document: StatementDocument) throws(ParseError) -> ParsedStatement {
        guard case let .layout(layout) = document.content else { throw .unsupportedFormat }
        let lines = layout.lines

        var currency: Currency?
        var period: DateInterval?
        var opening: Decimal?
        var totals: (income: Decimal, expense: Decimal)?
        for line in lines {
            let text = line.text
            if currency == nil, let match = text.firstMatch(of: /^Валюта кошелька: ([A-Z]{3})/) {
                currency = Currency(code: String(match.1))
            }
            if period == nil, let match = text.firstMatch(of: /(\d{2}\.\d{2}\.\d{4}) по (\d{2}\.\d{2}\.\d{4})/),
               let start = BYDate.date(String(match.1)), let end = BYDate.date(String(match.2)) {
                period = DateInterval(start: start, end: end.addingTimeInterval(86_399))
            }
            if opening == nil, let match = text.firstMatch(of: /^Остаток на начало периода: (-?\s?\d[\d ]*(?:\.\d+)?) [A-Z]{3}/) {
                opening = AmountParser.decimal(from: String(match.1))
            }
            // Суммы итогов могут быть с пробелом между разрядами: `1 240.0 1 235.75 BYN`,
            // поэтому каждая сумма — группы до трёх цифр, а между суммами пробел.
            if totals == nil, let match = text.firstMatch(of: /^Итого (\d{1,3}(?: \d{3})*(?:\.\d+)?) (\d{1,3}(?: \d{3})*(?:\.\d+)?) [A-Z]{3}/),
               let income = AmountParser.decimal(from: String(match.1)),
               let expense = AmountParser.decimal(from: String(match.2)) {
                totals = (income, expense)
            }
        }
        guard let currency else { throw .missingColumn("Валюта кошелька") }
        guard let header = lines.first(where: { line in line.words.contains { $0.text == "Приход" } }) else {
            throw .missingColumn("Шапка таблицы")
        }
        var boundaries: [CGFloat] = []
        for title in Self.headerStarts {
            guard let word = header.words.first(where: { $0.text == title }) else { throw .missingColumn(title) }
            boundaries.append(word.frame.minX - 2)
        }

        let tableLines = TableExtractor.tableLines(
            in: layout,
            isHeader: { $0.words.first?.text == "транзакции" },
            isFooter: { $0.words.first?.text == "Итого" }
        )
        let table = TableExtractor.rows(tableLines, boundaries: boundaries) { cells in
            cells[0].firstMatch(of: /^\d{2}\.\d{2}\.\d{4}/) != nil && cells[1].wholeMatch(of: /\d+/) != nil
        }

        var rows: [ParsedRow] = []
        var warnings: [ParseWarning] = []
        for (index, cells) in table.enumerated() {
            let income = AmountParser.decimal(from: cells[3])
            let expense = AmountParser.decimal(from: cells[4])
            guard let bookedAt = BYDate.dateTime(cells[0]),
                  cells[6].isEmpty || cells[6] == currency.code,
                  let value = income ?? expense.map({ -$0 }), (income == nil) != (expense == nil)
            else {
                warnings.append(ParseWarning(line: nil, message: "Не удалось разобрать операцию №\(index + 1): \(cells.joined(separator: " | "))"))
                continue
            }
            let description = Self.description(type: cells[2], details: cells[7])
            rows.append(ParsedRow(
                bookedAt: bookedAt,
                amount: Money(value, currency: currency),
                description: description,
                bankReference: "oplati:\(cells[1])"
            ))
        }

        if layout.uncertainWords > 0 {
            warnings.append(ParseWarning(
                line: nil,
                message: "Положение части текста в PDF определено неточно (\(layout.uncertainWords)): проверьте описания операций"
            ))
        }
        if let totals {
            let credited = rows.map(\.amount.decimalValue).filter { $0 > 0 }.reduce(0, +)
            let debited = -rows.map(\.amount.decimalValue).filter { $0 < 0 }.reduce(0, +)
            if credited != totals.income || debited != totals.expense {
                warnings.append(ParseWarning(
                    line: nil,
                    message: "Сумма операций не сходится с оборотами выписки: приход \(totals.income) и расход \(totals.expense), получилось \(credited) и \(debited)"
                ))
            }
        } else {
            warnings.append(BankParsersBY.noCheckWarning)
        }

        let closing = opening.flatMap { opening in totals.map { opening + $0.income - $0.expense } }
        return ParsedStatement(
            accountHint: AccountHint(currency: currency),
            period: period,
            openingBalance: opening.map { Money($0, currency: currency) },
            closingBalance: closing.map { Money($0, currency: currency) },
            rows: rows,
            warnings: warnings
        )
    }

    /// Описание из «Деталей». Тип платежа в узкой колонке перенесён посреди слова («Пополне ние кошельк а»),
    /// поэтому он сравнивается без пробелов. Вывод на карту в деталях называется «Перечисление средств»,
    /// без слова-признака перевода, и без него перевод между кошельком и картой не нашёлся бы:
    /// такой строке добавляется «Перевод:». Без деталей (оплата в ЕРИП) описание — сам тип.
    static func description(type: String, details: String) -> String {
        let compactType = type.filter { !$0.isWhitespace }.lowercased()
        guard !details.isEmpty else {
            return type.split(separator: " ").joined(separator: " ")
        }
        if compactType == "выводсредств" {
            return "Перевод: \(details)"
        }
        return details
    }
}
