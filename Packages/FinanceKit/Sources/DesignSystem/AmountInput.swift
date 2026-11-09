import Foundation

/// Сумма, введённая с клавиатуры. Строка, а не `TextField(value:format:)`: тот обновляет значение
/// только при подтверждении ввода, а у `.decimalPad` нет Return (#35).
public enum AmountInput {
    /// `12`, `12,5`, `1 250.40`: запятая или точка, пробелы между разрядами, до двух знаков после запятой.
    /// С `allowsNegative` допускается минус в начале (остаток кредитной карты): `-1 250,40`.
    public static func parse(_ text: String, allowsNegative: Bool = false) -> Decimal? {
        var text = text.trimmingCharacters(in: .whitespaces)
        text.removeAll { $0 == " " || $0 == "\u{00A0}" || $0 == "\u{202F}" }
        text = text.replacingOccurrences(of: ",", with: ".")
        // Минус с клавиатуры iOS иногда приходит как «−» (U+2212).
        var isNegative = false
        if allowsNegative, let first = text.first, first == "-" || first == "\u{2212}" {
            isNegative = true
            text.removeFirst()
        }
        guard text.wholeMatch(of: /\d+(?:\.\d{0,2})?|\.\d{1,2}/) != nil else { return nil }
        if text.hasPrefix(".") { text = "0" + text }
        guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return isNegative ? -value : value
    }

    /// Модуль суммы для поля ввода: `-12.5` → `12.5`. Знак задаёт переключатель «Расход / Доход».
    public static func text(for value: Decimal) -> String {
        let magnitude = value < 0 ? -value : value
        return "\(magnitude)"
    }

    /// Сумма со знаком для поля ввода: `-12.5` остаётся `-12.5`.
    public static func signedText(for value: Decimal) -> String {
        "\(value)"
    }
}
