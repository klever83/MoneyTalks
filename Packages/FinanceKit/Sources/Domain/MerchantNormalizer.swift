import Foundation

/// Приводит название мерчанта из выписки к человеческому виду:
/// `EVROOPT 123 MINSK BY` → `Evroopt`.
public enum MerchantNormalizer {
    private static let trailingNoise: Set<String> = [
        "BY", "BLR", "BELARUS", "MINSK", "МИНСК", "BREST", "GRODNO", "GOMEL", "VITEBSK", "MOGILEV",
    ]

    /// Ключ мерчанта для правил «всегда так»: у разных точек одной сети он один и тот же.
    /// Кроме шума из `normalize`, отбрасываются любые отдельные числа: `EVROOPT 12` и `EVROOPT 45` — одна сеть.
    public static func key(_ raw: String) -> String {
        normalize(raw.replacing(/\b\d+\b/, with: " ")).lowercased()
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
