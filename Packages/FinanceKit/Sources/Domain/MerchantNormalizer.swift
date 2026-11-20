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
        // Альфа-Банк: «g MINSK Покупка товара / получение услуг …», «… g MINSK».
        "ПОКУПКА", "ТОВАРА", "ТОВАРОВ", "G", "Г",
        // «Оплата товаров и услуг»: союз без мерчанта не должен становиться ключом.
        "И",
    ])

    /// Коды стран ISO 3166-1 alpha-3, после которых в выписках идёт место операции.
    /// Только те, что не совпадают с частыми словами в названиях (нет `ARE`, `BEL`, `IND`).
    private static let countryCodes: Set<String> = [
        "BLR", "RUS", "UKR", "POL", "LTU", "LVA", "EST", "GEO", "ARM", "AZE", "KAZ", "UZB", "KGZ", "TJK",
        "MDA", "TUR", "GBR", "USA", "DEU", "NLD", "IRL", "CYP", "CHE", "CZE", "SRB", "MNE", "ISR", "EGY",
        "THA", "CHN", "ESP", "FRA", "ITA", "GRC", "AUT", "BGR", "HUN", "SWE", "FIN",
    ]

    /// Ключ мерчанта для правил «всегда так»: у разных точек одной сети он один и тот же.
    /// Отбрасываются отдельные числа, служебные слова, страна и город в любом месте строки:
    /// `EVROOPT 12`, `Retail BLR MINSK EVROOPT 45` и `Безналичная оплата EVROOPT 12` дают `evroopt`.
    /// Место после кода страны тоже не входит: `Retail GEO TBILISI SPAR` даёт `spar`,
    /// `EVROPOCHTA BLR MINSKIY RAYON` — `evropochta`.
    /// Пустой ключ значит, что мерчанта в описании нет (P2P, ЕРИП, переводы).
    ///
    /// Сохранённые правила хранят ключ: при изменении функции их переводит миграция
    /// (`v12-merchant-key-place`, `v13-merchant-key-last-country`) с замороженной копией прежней
    /// функции, иначе «всегда так» молча перестанет срабатывать.
    public static func key(_ raw: String) -> String {
        withoutPlace(tokens(raw))
            .map(\.text)
            .filter { !isServiceToken($0) }
            .joined(separator: " ")
            .lowercased()
    }

    /// Сохранённый ключ без служебных слов текущей версии, без разбора места: для миграций,
    /// когда операций с этим ключом не осталось. Полный `key` на ключе не идемпотентен:
    /// в `super tur` он принял бы `TUR` за код страны.
    public static func withoutServiceWords(_ key: String) -> String {
        tokens(key)
            .map(\.text)
            .filter { !isServiceToken($0) }
            .joined(separator: " ")
            .lowercased()
    }

    /// Буквенно-цифровой кусок строки и номер слова (по пробелам), из которого он взят:
    /// город после кода страны — одно слово, даже если это `ITUNES.COM`.
    private struct Token {
        let text: String
        let word: Int
    }

    private static func tokens(_ raw: String) -> [Token] {
        raw.uppercased()
            .split(whereSeparator: \.isWhitespace)
            .enumerated()
            .flatMap { word, part in
                part.split { !($0.isLetter || $0.isNumber) }.map { Token(text: String($0), word: word) }
            }
    }

    private static func isServiceToken(_ token: String) -> Bool {
        token.allSatisfy(\.isNumber) || serviceWords.contains(token)
    }

    /// Убирает место операции по коду страны. Перед мерчантом (`Retail GEO TBILISI SPAR`,
    /// перед первым кодом только служебные слова) уходят код и город. После мерчанта
    /// (`EVROPOCHTA BLR, MINSKIY RAYON`) уходит всё от последнего кода до конца строки:
    /// код внутри названия (`SUPER TUR BLR, MINSK`) остаётся.
    /// Без служебных слов перед кодом строка не трогается: `USA NAILS` — это название.
    /// Город из нескольких слов (`Retail USA NEW YORK SHOP`) уходит только первым словом.
    private static func withoutPlace(_ tokens: [Token]) -> [Token] {
        // Альфа-Банк пишет место перед типом операции: `WARSZAWA Покупка товара / получение услуг SHOP`.
        if let index = tokens.indices.dropLast().first(where: { tokens[$0].text == "ПОКУПКА" && tokens[$0 + 1].text == "ТОВАРА" }) {
            return Array(tokens[index...])
        }
        let isCountry = { (token: Token) in countryCodes.contains(token.text) }
        guard let first = tokens.firstIndex(where: isCountry), first > 0 else { return tokens }
        let before = tokens[..<first]
        if before.contains(where: { !isServiceToken($0.text) }) {
            let last = tokens.lastIndex(where: isCountry) ?? first
            return Array(tokens[..<last])
        }
        // Город — остаток слова с кодом (`BLR,MINSK`) или следующее слово. Он уходит, только если
        // после него остаётся мерчант: в `Retail BLR EVROOPT 12` и `Retail NLD BOOKING.COM` города нет.
        let afterCode = tokens[(first + 1)...]
        let cityWord = afterCode.first { $0.word == tokens[first].word }?.word ?? afterCode.first?.word
        let afterCity = afterCode.drop { $0.word == cityWord }
        let rest = afterCity.contains(where: { !isServiceToken($0.text) }) ? afterCity.startIndex : first + 1
        return Array(before) + tokens[rest...]
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
