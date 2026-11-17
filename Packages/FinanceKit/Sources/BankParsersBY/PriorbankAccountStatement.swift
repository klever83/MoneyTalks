import CoreGraphics
import Domain
import Foundation
import StatementImport

/// Приорбанк: «Выписка по счету» — выписка по текущему счёту за произвольный период
/// (например, за два года), PDF в альбомной ориентации.
///
/// Это другой документ, чем «Выписка по контракту»: нет ни «prior.by», ни «Валюта счета:»,
/// время операций не указано, суммы без знака в двух колонках «Списание» и «Поступление».
/// Валюта счёта задана цифровым кодом («Код валюты - 933»), остатки — строками таблицы
/// «Входящий остаток» и «Исходящий остаток», обороты — строкой «Итого оборотов».
///
/// Шапка таблицы есть только на первой странице, ячейки выровнены по верху строки,
/// и строка операции может продолжаться на следующей странице. Поэтому колонки берутся
/// по словам шапки, а все строки без даты приклеиваются к последней операции.
enum PriorbankAccountStatement {
    /// Колонки таблицы слева направо.
    private enum Column: Int {
        case date, document, kind, details, place, debit, credit, balance
    }

    private static let currencyCodes = ["933": "BYN", "840": "USD", "978": "EUR", "643": "RUB"]

    /// Признаки выписки по счёту, которых нет в выписке по контракту.
    static func confidence(text: String) -> Double {
        var score = 0.0
        if text.contains("PJCBBY2X") || text.contains(/BY\d{2}PJCB/) { score += 0.4 }
        if text.contains("ПРИОРБАНК") || text.contains("Приорбанк ОАО") { score += 0.3 }
        if text.contains(/Выписка по сч[её]ту с \d{2}\.\d{2}\.\d{4}/) { score += 0.3 }
        return min(score, 1)
    }

    static func matches(_ text: String) -> Bool {
        !text.contains("Выписка по контракту") && text.contains("Входящий остаток") && confidence(text: text) >= 0.7
    }

    static func parse(_ layout: TextLayout) throws(ParseError) -> ParsedStatement {
        let lines = layout.lines
        let text = layout.text

        guard let found = Self.currency(in: text) else { throw .missingColumn("Код валюты") }
        let (currency, numericCode) = found
        var period: DateInterval?
        if let match = text.firstMatch(of: /Выписка по сч[её]ту с (\d{2}\.\d{2}\.\d{4}) по (\d{2}\.\d{2}\.\d{4})/),
           let start = BYDate.date(String(match.1)), let end = BYDate.date(String(match.2)) {
            period = DateInterval(start: start, end: end.addingTimeInterval(86_399))
        }
        let account = lines
            .first { $0.text.contains("IBAN") }?
            .text.firstMatch(of: /BY\d{2}PJCB[0-9A-Z]+/)
            .map { String($0.output) }

        guard let headerIndex = lines.firstIndex(where: { line in line.words.contains { $0.text == "Детализация" } })
        else { throw .missingColumn("Шапка таблицы") }
        let boundaries = try columnBoundaries(header: lines[headerIndex], following: lines[(headerIndex + 1)...])

        var opening: Decimal?
        var closing: Decimal?
        var totals: (debit: Decimal, credit: Decimal)?
        var drafts: [Draft] = []
        for line in lines[headerIndex...] {
            let text = line.text
            if text.hasPrefix("Входящий остаток") {
                opening = balance(in: text)
                continue
            }
            if text.hasPrefix("Итого оборотов") {
                let values = amounts(in: text)
                if values.count >= 2 { totals = (values[values.count - 2], values[values.count - 1]) }
                continue
            }
            if text.hasPrefix("Исходящий остаток") {
                closing = balance(in: text)
                break
            }
            let cells = TableExtractor.cells(of: line, boundaries: boundaries)
            if let date = BYDate.date(cells[Column.date.rawValue]) {
                drafts.append(Draft(number: drafts.count + 1, bookedAt: date, cells: cells.map { $0.isEmpty ? [] : [$0] }))
            } else if !drafts.isEmpty {
                // Продолжение ячеек последней операции, в том числе с начала следующей страницы.
                for (column, cell) in cells.enumerated() where !cell.isEmpty {
                    drafts[drafts.count - 1].cells[column].append(cell)
                }
            }
        }

        var parsed: [(row: ParsedRow, isOverdraft: Bool)] = []
        var warnings: [ParseWarning] = []
        var debited: Decimal = 0
        var credited: Decimal = 0
        for draft in drafts {
            guard let debit = AmountParser.decimal(from: draft.cell(.debit)),
                  let credit = AmountParser.decimal(from: draft.cell(.credit)),
                  (debit == 0) != (credit == 0)
            else {
                warnings.append(ParseWarning(line: nil, message: "Не удалось разобрать операцию №\(draft.number): \(draft.summary)"))
                continue
            }
            debited += debit
            credited += credit
            let row = ParsedRow(
                bookedAt: draft.bookedAt,
                amount: Money(credit - debit, currency: currency),
                description: draft.description
            )
            parsed.append((row, draft.isTechnicalOverdraft))
        }

        // Учёт и погашение технического овердрафта — внутренние проводки банка: учёт закрывает минус
        // на счёте, погашение возвращает его, когда приходят деньги. В расходы и доходы они не идут.
        // Пропускаем их, только если за период они гасят друг друга, иначе не сойдётся остаток.
        let overdraft = parsed.filter(\.isOverdraft).map(\.row)
        var rows = parsed.map(\.row)
        if !overdraft.isEmpty {
            let net = overdraft.reduce(Decimal(0)) { $0 + $1.amount.decimalValue }
            if net == 0 {
                rows = parsed.filter { !$0.isOverdraft }.map(\.row)
                warnings.append(ParseWarning(
                    line: nil,
                    message: "Учёт и погашение технического овердрафта — внутренние проводки банка, пропущено (\(overdraft.count))"
                ))
            } else {
                warnings.append(ParseWarning(
                    line: nil,
                    message: "Технический овердрафт за период не закрыт (\(net)): его проводки импортированы как операции"
                ))
            }
        }

        if layout.uncertainWords > 0 {
            warnings.append(ParseWarning(
                line: nil,
                message: "Положение части текста в PDF определено неточно (\(layout.uncertainWords)): проверьте описания операций"
            ))
        }
        if let totals, totals.debit != debited || totals.credit != credited {
            warnings.append(ParseWarning(
                line: nil,
                message: "Сумма операций не сходится с оборотами выписки: списано \(totals.debit) и поступило \(totals.credit), "
                    + "получилось \(debited) и \(credited)"
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
        } else if totals == nil {
            warnings.append(BankParsersBY.noCheckWarning)
        }

        return ParsedStatement(
            accountHint: AccountHint(maskedNumber: account.map { maskedNumber(iban: $0, numericCode: numericCode) }, currency: currency),
            period: period,
            openingBalance: opening.map { Money($0, currency: currency) },
            closingBalance: closing.map { Money($0, currency: currency) },
            rows: rows,
            warnings: warnings
        )
    }

    // MARK: - Операция

    private struct Draft {
        /// Порядковый номер операции в выписке: для сообщений.
        var number: Int
        var bookedAt: Date
        /// Строки текста каждой колонки сверху вниз.
        var cells: [[String]]

        func cell(_ column: Column) -> String {
            cells[column.rawValue].joined(separator: " ")
        }

        /// «Списание по реестру карт-центра (-)» → «Списание по реестру карт-центра».
        var kind: String {
            cell(.kind).replacing(/\s*\([+-]\)$/, with: "")
        }

        var isTechnicalOverdraft: Bool {
            kind.hasPrefix("Учет технического овердрафта") || kind.hasPrefix("Погашение технического овердрафта")
        }

        /// У карточных операций вид операции одинаковый и ничего не говорит: описание — мерчант и место.
        /// У остальных вид операции важен (проценты, зарплата, перевод), детализация дополняет его.
        var description: String {
            let isCard = kind.hasPrefix("Списание по реестру") || kind.hasPrefix("Зачисление по реестру")
            let place = cell(.place)
            let usefulPlace = place.contains(where: \.isLetter) && !place.hasPrefix("Приорбанк ОАО") ? place : ""
            let details = self.details
            let parts = isCard && !details.isEmpty ? [details, usefulPlace] : [kind, details, usefulPlace]
            // Пустое место у карточных операций — одинокая «,»: PDFKit может приклеить её к мерчанту.
            return parts.filter { !$0.isEmpty }.joined(separator: " ").trimmingCharacters(in: Self.edgeNoise)
        }

        private static let edgeNoise = CharacterSet(charactersIn: " ,")

        /// Детализация без реквизитов: у зачислений по ведомости за назначением платежа идут
        /// плательщик, его счёт, УНП и прочее, в описание это не нужно.
        private var details: String {
            var lines: [String] = []
            for line in cells[Column.details.rawValue] {
                if line.hasPrefix("Плательщик") || line.hasPrefix("Получатель") || line.hasPrefix("Комиссионное") { break }
                lines.append(line)
                if lines.count == 3 { break }
            }
            return lines.joined(separator: " ")
        }

        var summary: String {
            cells.map { $0.joined(separator: " ") }.filter { !$0.isEmpty }.joined(separator: " | ")
        }
    }

    // MARK: - Шапка

    /// Границы колонок по словам шапки: середины просветов между заголовками соседних колонок.
    /// Шапка в четыре строки, а «Обороты» и «Корреспондент» стоят над двумя колонками сразу,
    /// поэтому общий поиск просветов не годится: берём заголовки по именам.
    private static func columnBoundaries(header: TextLine, following: ArraySlice<TextLine>) throws(ParseError) -> [CGFloat] {
        // Шапка кончается на строке остатка или первой операции.
        let headerLines = following.prefix { line in
            line.frame.minY > header.frame.minY
                && !line.text.hasPrefix("Входящий остаток")
                && BYDate.date(line.words.first?.text ?? "") == nil
        }
        let words = ([header] + headerLines).flatMap(\.words)
        func word(_ text: String) -> TextWord? { words.first { $0.text == text } }
        guard let number = word("№") ?? word("док"),
              let kind = word("Вид"),
              let details = word("Детализация"),
              let debit = word("Списание"),
              let credit = word("Поступление"),
              let balance = word("Остаток"),
              let bank = word("Банк")
        else { throw .missingColumn("Шапка таблицы") }
        let placeLeft = words
            .filter { $0.text == "Место" || $0.text == "проведения" }
            .map(\.frame.minX)
            .min() ?? (details.frame.maxX + debit.frame.minX) / 2

        /// Правый край заголовка колонки: самое правое слово шапки между её левым краем и следующей колонкой.
        func right(from left: CGFloat, before next: CGFloat) -> CGFloat {
            words.filter { $0.frame.minX >= left - 1 && $0.frame.maxX < next }.map(\.frame.maxX).max() ?? left
        }
        let dateRight = words.filter { $0.frame.maxX < number.frame.minX }.map(\.frame.maxX).max() ?? number.frame.minX
        let spans: [(left: CGFloat, right: CGFloat)] = [
            (0, dateRight),
            (number.frame.minX, right(from: number.frame.minX, before: kind.frame.minX)),
            (kind.frame.minX, right(from: kind.frame.minX, before: details.frame.minX)),
            (details.frame.minX, right(from: details.frame.minX, before: placeLeft)),
            (placeLeft, right(from: placeLeft, before: debit.frame.minX)),
            (debit.frame.minX, debit.frame.maxX),
            (credit.frame.minX, credit.frame.maxX),
            (balance.frame.minX, balance.frame.maxX),
            (bank.frame.minX, bank.frame.maxX),
        ]
        let boundaries = zip(spans, spans.dropFirst()).map { ($0.right + $1.left) / 2 }
        guard zip(boundaries, boundaries.dropFirst()).allSatisfy({ $0 < $1 }) else { throw .missingColumn("Шапка таблицы") }
        return boundaries
    }

    // MARK: - Числа

    /// «Код валюты - 933 (Белорусский рубль)» или «… счета в BYN …» в типе договора.
    /// Вместе с валютой — её цифровой код, если он есть в шапке.
    private static func currency(in text: String) -> (Currency, numericCode: String?)? {
        let numeric = text.firstMatch(of: /Код валюты - (\d{3})/).map { String($0.1) }
        if let numeric, let code = currencyCodes[numeric] {
            return (Currency(code: code), numeric)
        }
        if let match = text.firstMatch(of: /Тип договора[^\n]*? в ([A-Z]{3})\b/) {
            return (Currency(code: String(match.1)), numeric)
        }
        return nil
    }

    /// Последние 4 цифры счёта для сопоставления со счётом приложения. IBAN Приорбанка кончается
    /// цифровым кодом валюты («…933»), а перед ним идёт номер договора: берём 4 цифры перед кодом,
    /// иначе у двух рублёвых счетов маски почти всегда совпадали бы.
    static func maskedNumber(iban: String, numericCode: String?) -> String {
        if let numericCode, iban.hasSuffix(numericCode) {
            return String(iban.dropLast(numericCode.count).suffix(4))
        }
        return String(iban.suffix(4))
    }

    /// Остаток из строки «Входящий остаток | дебет | кредит»: положительный остаток стоит в кредите.
    private static func balance(in text: String) -> Decimal? {
        let values = amounts(in: text)
        guard values.count >= 2 else { return nil }
        return values[values.count - 1] - values[values.count - 2]
    }

    /// Суммы вида `1,972.11` и `-12.30`.
    private static func amounts(in text: String) -> [Decimal] {
        text.matches(of: /-?\d{1,3}(?:,\d{3})*\.\d{2}/).compactMap { AmountParser.decimal(from: String($0.output)) }
    }
}
