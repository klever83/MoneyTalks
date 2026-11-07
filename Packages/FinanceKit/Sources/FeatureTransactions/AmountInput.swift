import Foundation

/// Сумма, введённая с клавиатуры. Строка, а не `TextField(value:format:)`: тот обновляет значение
/// только при подтверждении ввода, а у `.decimalPad` нет Return (#35).
enum AmountInput {
    /// `12`, `12,5`, `1 250.40`: запятая или точка, пробелы между разрядами, до двух знаков после запятой.
    static func parse(_ text: String) -> Decimal? {
        var text = text.trimmingCharacters(in: .whitespaces)
        text.removeAll { $0 == " " || $0 == "\u{00A0}" || $0 == "\u{202F}" }
        text = text.replacingOccurrences(of: ",", with: ".")
        guard text.wholeMatch(of: /\d+(?:\.\d{0,2})?|\.\d{1,2}/) != nil else { return nil }
        if text.hasPrefix(".") { text = "0" + text }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Модуль суммы для поля ввода: `-12.5` → `12.5`. Знак задаёт переключатель «Расход / Доход».
    static func text(for value: Decimal) -> String {
        let magnitude = value < 0 ? -value : value
        return "\(magnitude)"
    }
}
