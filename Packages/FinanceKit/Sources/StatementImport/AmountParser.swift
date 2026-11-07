import Foundation

/// Разбор сумм в форматах выписок: `1 234,56`, `-12.30`, `1,234.56`, `+15,00`, `- 11.45`, `−5,00`.
///
/// Строка проверяется целиком: если после нормализации осталось что-то кроме знака,
/// цифр и одного десятичного разделителя, возвращается `nil`, а не числовой префикс.
public enum AmountParser {
    public static func decimal(from string: String) -> Decimal? {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        // Пробелы-разделители тысяч и пробел между знаком и числом (`- 11.45` у БНБ):
        // обычный, неразрывный, узкий неразрывный.
        text.removeAll { $0 == " " || $0 == "\u{00A0}" || $0 == "\u{202F}" }
        // Юникодный минус и дефисы, которые попадаются в PDF вместо `-`.
        text = String(text.map { minusLookalikes.contains($0) ? "-" : $0 })
        guard !text.isEmpty else { return nil }

        let lastComma = text.lastIndex(of: ",")
        let lastDot = text.lastIndex(of: ".")
        if let lastComma, let lastDot {
            // Десятичный разделитель — тот, что правее; второй разделяет тысячи.
            if lastComma > lastDot {
                text.removeAll { $0 == "." }
                text = text.replacingOccurrences(of: ",", with: ".")
            } else {
                text.removeAll { $0 == "," }
            }
        } else if lastComma != nil {
            text = text.replacingOccurrences(of: ",", with: ".")
        }
        if text.hasPrefix("+") { text.removeFirst() }
        // `Decimal(string:)` разбирает числовой префикс и молча отбрасывает хвост
        // (`1.234.567` → 1.234, `12-30` → 12), поэтому форму проверяем сами.
        guard text.wholeMatch(of: /-?\d+(?:\.\d+)?/) != nil else { return nil }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static let minusLookalikes: Set<Character> = ["\u{2212}", "\u{2012}", "\u{2013}", "\u{2014}", "\u{FE63}", "\u{FF0D}"]
}
