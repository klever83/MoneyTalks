import Domain
import Foundation
import StatementImport

/// Приорбанк: «Выписка по контракту» из интернет-банка, PDF (экспорт из Word).
///
/// Строка операции: дата и время, операция (тип, страна, город, мерчант), сумма и валюта операции,
/// дата проведения, комиссия, обороты в валюте счёта. Текст в PDF чистый, поэтому строки
/// разбираются по просветам между ячейками, без поиска колонок.
/// Раздел «Заблокированные суммы» не импортируется: эти операции придут проведёнными в следующей выписке.
/// «Гашение основного долга» тоже: банк показывает его в контракте, но не включает в обороты и баланс.
public struct PriorbankParser: StatementParser {
    public let id: ParserID = "by.priorbank.pdf"
    public let bank = BankParsersBY.priorbank
    public let formats: Set<StatementFormat> = [.pdf]

    /// Просвет между ячейками строки: шире пробела между словами, уже расстояния между колонками.
    private let cellGap: CGFloat = 6

    public init() {}

    public func confidence(for document: StatementDocument) -> Double {
        guard case let .layout(layout) = document.content else { return 0 }
        let text = layout.text
        var score = 0.0
        if text.contains("prior.by") { score += 0.6 }
        if text.contains("Выписка по контракту") { score += 0.3 }
        if text.contains("Обороты") { score += 0.1 }
        return min(score, 1)
    }

    public func parse(_ document: StatementDocument) throws(ParseError) -> ParsedStatement {
        guard case let .layout(layout) = document.content else { throw .unsupportedFormat }
        let lines = layout.lines

        // В контракте может быть несколько счетов в разных валютах, у каждого свой блок
        // «Валюта счета: … Начальный баланс: …» и свои итоги. Импортируем блок первой валюты.
        var accountCurrency: Currency?
        var contractCurrency: Currency?
        var otherCurrencies: [String] = []
        var otherCurrencyRows = 0
        var inOtherCurrency = false
        var cardNumber: String?
        var period: DateInterval?
        var opening: Decimal?
        var closing: Decimal?
        var drafts: [(line: Int, row: Draft)] = []
        var warnings: [ParseWarning] = []
        var blockedCount = 0
        var inBlockedSection = false
        // Последняя строка операции: к ней приклеиваются перенесённые строки описания.
        var lastRow: (number: Int, frame: CGRect, description: ClosedRange<CGFloat>)?

        for (index, line) in lines.enumerated() {
            let text = line.text
            if contractCurrency == nil, let match = text.firstMatch(of: /Валюта контракта ([A-Z]{3})/) {
                contractCurrency = Currency(code: String(match.1))
            }
            if let match = text.firstMatch(of: /Валюта счета: ([A-Z]{3})/) {
                let code = String(match.1)
                if accountCurrency == nil { accountCurrency = Currency(code: code) }
                inOtherCurrency = code != accountCurrency?.code
                if inOtherCurrency, !otherCurrencies.contains(code) { otherCurrencies.append(code) }
                inBlockedSection = false
            }
            if cardNumber == nil, let match = text.firstMatch(of: /Карта: \.+(\d{4})/) {
                cardNumber = String(match.1)
            }
            if period == nil, let match = text.firstMatch(of: /Период выписки (\d{2}\.\d{2}\.\d{4}) - (\d{2}\.\d{2}\.\d{4})/),
               let start = Self.date(String(match.1)), let end = Self.date(String(match.2)) {
                period = DateInterval(start: start, end: end.addingTimeInterval(86_399))
            }
            if opening == nil, !inOtherCurrency, let match = text.firstMatch(of: /Начальный баланс: (-?[\d ]+\.\d{2})/) {
                opening = AmountParser.decimal(from: String(match.1))
            }
            if text.hasPrefix("Всего в данной валюте"), !inOtherCurrency, closing == nil, index + 1 < lines.count {
                // Строка под заголовком итогов: зачислено, списано, комиссия, конечный баланс.
                closing = Self.amounts(in: lines[index + 1].text).last
            }
            if text.hasPrefix("Заблокированные суммы") {
                inBlockedSection = true
                lastRow = nil
                continue
            }
            if text.hasPrefix("Операции по") {
                inBlockedSection = false
            }

            let segments = line.segmentWords(minGap: cellGap)
            let texts = segments.map { $0.map(\.text).joined(separator: " ") }
            guard let first = texts.first, let bookedAt = Self.dateTime(first) else {
                if let last = lastRow, drafts.last?.line == last.number,
                   Self.isContinuation(line.frame, below: last.frame, description: last.description) {
                    drafts[drafts.count - 1].row.description += " " + text
                    lastRow?.frame = line.frame
                } else {
                    lastRow = nil
                }
                continue
            }
            lastRow = nil
            if inOtherCurrency {
                otherCurrencyRows += 1
                continue
            }
            if inBlockedSection {
                blockedCount += 1
                continue
            }
            if texts.count > 1, texts[1].hasPrefix("Гашение основного долга") {
                warnings.append(ParseWarning(line: index + 1, message: "Гашение основного долга не влияет на баланс счёта, пропущено"))
                continue
            }
            guard texts.count >= 6, let draft = Self.draft(from: texts, bookedAt: bookedAt) else {
                warnings.append(ParseWarning(line: index + 1, message: "Не удалось разобрать операцию: \(text)"))
                continue
            }
            if let commission = draft.commission, commission != 0 {
                warnings.append(ParseWarning(
                    line: index + 1,
                    message: "Комиссия/Money-back \(commission) не выделена в отдельную операцию: проверьте сумму «\(draft.description)»"
                ))
            }
            drafts.append((index + 1, draft))
            // Описание — ячейки между датой и пятью последними колонками; перенос должен лечь в те же границы.
            let descriptionWords = segments.dropFirst().dropLast(5).flatMap { $0 }
            if let minX = descriptionWords.map(\.frame.minX).min(),
               let amountMinX = segments.dropLast(4).last?.map(\.frame.minX).min() {
                lastRow = (index + 1, line.frame, minX...amountMinX)
            }
        }

        guard let accountCurrency = accountCurrency ?? contractCurrency else { throw .missingColumn("Валюта счета") }
        if !otherCurrencies.isEmpty {
            warnings.append(ParseWarning(
                line: nil,
                message: "В контракте несколько валют счёта: импортированы операции в \(accountCurrency.code), "
                    + "пропущено \(otherCurrencyRows) в \(otherCurrencies.joined(separator: ", ")). Импортируйте их отдельной выпиской"
            ))
        }

        var rows: [ParsedRow] = []
        for (line, draft) in drafts {
            guard let row = draft.row(accountCurrency: accountCurrency) else {
                warnings.append(ParseWarning(line: line, message: "Не удалось разобрать сумму операции"))
                continue
            }
            rows.append(row)
        }

        if layout.uncertainWords > 0 {
            warnings.append(ParseWarning(
                line: nil,
                message: "Положение части текста в PDF определено неточно (\(layout.uncertainWords)): проверьте описания операций"
            ))
        }
        if blockedCount > 0 {
            warnings.append(ParseWarning(
                line: nil,
                message: "Заблокированные суммы не импортированы (\(blockedCount)): они появятся после проведения"
            ))
        }
        // Самопроверка: начальный баланс плюс обороты должен дать конечный.
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
            accountHint: AccountHint(maskedNumber: cardNumber, currency: accountCurrency),
            period: period,
            openingBalance: opening.map { Money($0, currency: accountCurrency) },
            closingBalance: closing.map { Money($0, currency: accountCurrency) },
            rows: rows,
            warnings: warnings
        )
    }

    // MARK: - Строка операции

    private struct Draft {
        var bookedAt: Date
        var description: String
        var amount: Decimal
        var currency: Currency
        var accountAmount: Decimal
        var commission: Decimal?

        func row(accountCurrency: Currency) -> ParsedRow? {
            let signed = Money(accountAmount, currency: accountCurrency)
            var original: Money?
            if currency != accountCurrency {
                // Сумма операции в выписке бывает без знака (гашение долга), знак берём из оборотов.
                let magnitude = abs(amount)
                original = Money(signed.isNegative ? -magnitude : magnitude, currency: currency)
            }
            return ParsedRow(bookedAt: bookedAt, amount: signed, originalAmount: original, description: description)
        }
    }

    /// `[дата время] [операция…] [сумма] [валюта] [дата проведения] [комиссия] [обороты]`
    private static func draft(from segments: [String], bookedAt: Date) -> Draft? {
        let tail = segments.suffix(5)
        let values = Array(tail)
        guard values[1].wholeMatch(of: /[A-Z]{3}/) != nil,
              date(values[2]) != nil,
              let amount = AmountParser.decimal(from: values[0]),
              let accountAmount = AmountParser.decimal(from: values[4])
        else { return nil }
        let description = segments.dropFirst().dropLast(5).joined(separator: " ")
        return Draft(
            bookedAt: bookedAt,
            description: description,
            amount: amount,
            currency: Currency(code: values[1]),
            accountAmount: accountAmount,
            commission: AmountParser.decimal(from: values[3])
        )
    }

    /// Перенесённая строка описания: сразу под строкой операции, в границах колонки «Операция».
    private static func isContinuation(_ frame: CGRect, below previous: CGRect, description: ClosedRange<CGFloat>) -> Bool {
        let gap = frame.minY - previous.maxY
        return gap >= -1 && gap < previous.height
            && frame.minX >= description.lowerBound - 2
            && frame.maxX <= description.upperBound
    }

    // MARK: - Числа и даты

    private static func amounts(in text: String) -> [Decimal] {
        text.matches(of: /-?\d+(?: \d{3})*\.\d{2}/).compactMap { AmountParser.decimal(from: String($0.output)) }
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Minsk") ?? .current
        return calendar
    }

    static func date(_ text: String) -> Date? {
        guard let match = text.wholeMatch(of: /(\d{2})\.(\d{2})\.(\d{4})/) else { return nil }
        return calendar.date(from: DateComponents(year: Int(match.3), month: Int(match.2), day: Int(match.1)))
    }

    static func dateTime(_ text: String) -> Date? {
        guard let match = text.wholeMatch(of: /(\d{2})\.(\d{2})\.(\d{4}) (\d{2}):(\d{2}):(\d{2})/) else { return nil }
        return calendar.date(from: DateComponents(
            year: Int(match.3), month: Int(match.2), day: Int(match.1),
            hour: Int(match.4), minute: Int(match.5), second: Int(match.6)
        ))
    }
}
