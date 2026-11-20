import Foundation

/// `MerchantNormalizer.key` из #88, замороженный: по нему записаны ключи правил, которые
/// прошли `v12-merchant-key-place` в той версии (симулятор, сборки за полчаса до #89).
/// Их переводит `v13-merchant-key-last-country`. Не менять.
enum MerchantKeyV2 {
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
    /// (`v12-merchant-key-place`), иначе «всегда так» молча перестанет срабатывать.
    static func key(_ raw: String) -> String {
        withoutPlace(tokens(raw))
            .filter { !isServiceToken($0) }
            .joined(separator: " ")
            .lowercased()
    }

    private static func tokens(_ raw: String) -> [String] {
        raw.uppercased()
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
    }

    private static func isServiceToken(_ token: String) -> Bool {
        token.allSatisfy(\.isNumber) || serviceWords.contains(token)
    }

    /// Убирает место операции по первому коду страны. Перед мерчантом (`Retail GEO TBILISI SPAR`,
    /// перед кодом только служебные слова) уходят код и город. После мерчанта
    /// (`EVROPOCHTA BLR MINSKIY RAYON`) уходит всё от кода до конца строки.
    /// Без служебных слов перед кодом строка не трогается: `USA NAILS` — это название.
    /// Город из нескольких слов (`Retail USA NEW YORK SHOP`) уходит только первым словом.
    private static func withoutPlace(_ tokens: [String]) -> [String] {
        // Альфа-Банк пишет место перед типом операции: `WARSZAWA Покупка товара / получение услуг SHOP`.
        if let index = tokens.indices.dropLast().first(where: { tokens[$0] == "ПОКУПКА" && tokens[$0 + 1] == "ТОВАРА" }) {
            return Array(tokens[index...])
        }
        guard let index = tokens.firstIndex(where: countryCodes.contains), index > 0 else { return tokens }
        let before = tokens[..<index]
        if before.contains(where: { !isServiceToken($0) }) {
            return Array(before)
        }
        // Город — одно слово после кода, если за ним ещё что-то есть: иначе это и есть мерчант.
        let rest = index + 2 < tokens.count ? index + 2 : index + 1
        return Array(before) + tokens[rest...]
    }
}
