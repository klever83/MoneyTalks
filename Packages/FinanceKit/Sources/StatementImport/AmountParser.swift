import Foundation

/// Разбор сумм в форматах выписок: `1 234,56`, `-12.30`, `1,234.56`, `+15,00`.
public enum AmountParser {
    public static func decimal(from string: String) -> Decimal? {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        // Пробелы-разделители тысяч: обычный, неразрывный, узкий неразрывный.
        text.removeAll { $0 == " " || $0 == "\u{00A0}" || $0 == "\u{202F}" }
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
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }
}
