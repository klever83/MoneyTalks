import Foundation

/// Приводит название мерчанта из выписки к человеческому виду:
/// `EVROOPT 123 MINSK BY` → `Evroopt`.
public enum MerchantNormalizer {
    private static let trailingNoise: Set<String> = [
        "BY", "BLR", "BELARUS", "MINSK", "МИНСК", "BREST", "GRODNO", "GOMEL", "VITEBSK", "MOGILEV",
    ]

    /// Служебные слова выписок: тип операции, канал, страна и город. В ключ мерчанта не входят.
    /// У P2P, переводов и ЕРИП «мерчант» — это тип операции, и после их удаления ключ пустой.
    private static let serviceWords: Set<String> = trailingNoise.union([
        "RETAIL", "CH", "DEBIT", "CREDIT", "SDBO", "NO", "FEE", "P2P", "ATM", "CASH", "CARD", "BANK",
        "TRANSFER", "PAYMENT", "FROM", "TO", "POPOLNENIE", "ERIP",
        "МИНСК", "ЕРИП", "ОПЛАТА", "ОПЛАТЫ", "УСЛУГ", "УСЛУГИ", "БЕЗНАЛИЧНАЯ", "ПЕРЕВОД", "ПЕРЕВОДА",
        "ЗАЧИСЛЕНИЕ", "СПИСАНИЕ", "ПОПОЛНЕНИЕ", "ПОСТУПЛЕНИЕ", "ВОЗВРАТ", "ОБМЕН", "КОНВЕРСИЯ",
        "СНЯТИЕ", "ПОЛУЧЕНИЕ", "НАЛИЧНЫХ", "КОМИССИЯ", "КАРТЫ", "КАРТУ", "КАРТА", "СЧЁТ", "СЧЕТ", "СЧЕТА",
        "НА", "С", "СО", "ПО", "ЗА", "В", "ОТ",
    ])

    /// Ключ мерчанта для правил «всегда так»: у разных точек одной сети он один и тот же.
    /// Отбрасываются отдельные числа, служебные слова, страна и город в любом месте строки:
    /// `EVROOPT 12`, `Retail BLR MINSK EVROOPT 45` и `Безналичная оплата EVROOPT` дают `evroopt`.
    /// Пустой ключ значит, что мерчанта в описании нет (P2P, ЕРИП, переводы).
    public static func key(_ raw: String) -> String {
        raw.uppercased()
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
            .filter { token in !token.allSatisfy(\.isNumber) && !serviceWords.contains(token) }
            .joined(separator: " ")
            .lowercased()
    }

    public static func normalize(_ raw: String) -> String {
        var text = raw.uppercased()
        text = text.replacingOccurrences(of: "*", with: " ")
        // Номера терминалов и точек продаж.
        text = text.replacing(/\b\d{3,}\b/, with: " ")
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        while let last = words.last, words.count > 1, trailingNoise.contains(last) {
            words.removeLast()
        }
        let joined = words.joined(separator: " ")
        guard !joined.isEmpty else { return raw.trimmingCharacters(in: .whitespacesAndNewlines) }
        return joined.capitalized(with: Locale(identifier: "ru_BY"))
    }
}
