import Domain
import Foundation

/// Встроенные правила: популярные мерчанты Беларуси и диапазоны MCC.
///
/// Живут в коде, а не в базе: обновляются вместе с приложением. Правила пользователя
/// всегда важнее (`RuleCategorizer`), а внутри встроенных мерчант важнее MCC.
/// Категории — системные, по `systemKey`: их ID одинаковы на всех устройствах.
public enum BuiltInRules {
    static let merchantPriority = 100
    static let mccPriority = 50

    public static let all: [CategoryRule] = merchantRules + mccRules

    // MARK: - Мерчанты

    /// Подстроки достаточно длинные, чтобы не совпасть случайно; короткие названия — отдельным словом.
    private static let merchants: [(key: String, contains: [String], words: [String])] = [
        ("groceries", [
            "EVROOPT", "ЕВРООПТ", "GIPPO", "ГИППО", "KORONA", "КОРОНА", "ALMI", "АЛМИ",
            "BELMARKET", "БЕЛМАРКЕТ", "RUBLEVSKIY", "РУБЛЕВСКИЙ", "SOSEDI", "СОСЕДИ",
            "VITALUR", "ВИТАЛЮР", "GROSHYK", "ГРОШЫК", "HIT DISKONT", "ХИТ ДИСКОНТ", "MART INN",
        ], ["SANTA", "САНТА", "GREEN", "ГРИН"]),
        ("cafes", [
            "MCDONALD", "МАКДОНАЛДС", "BURGER KING", "VKUSNO I TOCHKA", "ВКУСНО И ТОЧКА",
            "STARBUCKS", "COFFEE", "КОФЕЙНЯ", "PAPA JOHNS", "DOMINOS", "DODO PIZZA", "ДОДО ПИЦЦА",
            "LIDO", "ЛИДО",
        ], ["KFC"]),
        ("taxi", [
            "YANDEX GO", "YANDEX*GO", "YANDEX.GO", "YANDEX.TAXI", "ЯНДЕКС GO", "ЯНДЕКС ТАКСИ",
            "UBER", "TAXI", "ТАКСИ",
        ], []),
        ("transport", [
            "BELARUSNEFT", "БЕЛОРУСНЕФТЬ", "LUKOIL", "ЛУКОЙЛ", "GAZPROMNEFT", "ГАЗПРОМНЕФТЬ",
            "METROPOLITEN", "МЕТРОПОЛИТЕН", "BELZHD", "BELARUSKAYA ZHELEZNAYA", "БЕЛОРУССКАЯ ЖЕЛЕЗНАЯ",
        ], ["A-100", "БЖД"]),
        ("housing", [
            "ЖКХ", "ЖЭС", "КОММУНАЛ", "МИНСКЭНЕРГО", "ЭНЕРГОСБЫТ", "ВОДОКАНАЛ", "ГОРГАЗ", "ОБЛГАЗ",
            "MINSKENERGO", "VODOKANAL",
        ], []),
        ("telecom", [
            "BELTELECOM", "БЕЛТЕЛЕКОМ", "ZALA", "BYFLY", "LIFE:)",
        ], ["MTS", "МТС", "A1"]),
        ("health", [
            "APTEKA", "АПТЕКА", "PHARMACY", "БЕЛФАРМАЦИЯ", "BELFARMACIYA", "LODE", "ЛОДЭ",
            "СТОМАТОЛОГ", "STOMATOLOG", "МЕДЦЕНТР", "MEDCENTR",
        ], []),
        ("clothes", [
            "ZARA", "LC WAIKIKI", "MARK FORMELLE", "МАРК ФОРМЭЛЬ", "MILAVITSA", "МИЛАВИЦА",
            "BELWEST", "БЕЛВЕСТ", "SPORTMASTER", "СПОРТМАСТЕР", "RESERVED", "BERSHKA", "PULL&BEAR",
        ], []),
        ("subscriptions", [
            "NETFLIX", "SPOTIFY", "APPLE.COM/BILL", "ICLOUD", "YOUTUBE", "YANDEX PLUS", "ЯНДЕКС ПЛЮС",
            "KINOPOISK", "КИНОПОИСК", "OPENAI", "CHATGPT",
        ], ["OKKO", "IVI"]),
        ("entertainment", [
            "SILVER SCREEN", "MOOON", "KINOTEATR", "КИНОТЕАТР", "STEAMGAMES", "STEAM PURCHASE",
            "PLAYSTATION", "BILETY", "TICKETPRO",
        ], []),
        ("travel", [
            "BOOKING.COM", "AIRBNB", "BELAVIA", "БЕЛАВИА", "AVIASALES", "RYANAIR", "WIZZ AIR", "WIZZAIR",
        ], []),
        ("education", [
            "COURSERA", "UDEMY", "SKILLBOX", "DUOLINGO",
        ], []),
    ]

    private static let merchantRules: [CategoryRule] = {
        var rules: [CategoryRule] = []
        for entry in merchants {
            for text in entry.contains {
                rules.append(rule(entry.key, [.merchantContains(text)], priority: merchantPriority, name: "contains:\(text)"))
            }
            for word in entry.words {
                rules.append(rule(entry.key, [.merchantWord(word)], priority: merchantPriority, name: "word:\(word)"))
            }
        }
        // Зарплата: только поступления.
        for text in ["ЗАРАБОТН", "ЗАРПЛАТ", "SALARY"] {
            rules.append(rule("salary", [.merchantContains(text), .amountSign(.positive)], priority: merchantPriority, name: "salary:\(text)"))
        }
        return rules
    }()

    // MARK: - MCC

    /// Коды по справочнику Visa/Mastercard. Знак суммы не проверяется: возврат покупки
    /// получает ту же категорию и уменьшает расходы (#36).
    private static let mcc: [(key: String, ranges: [ClosedRange<Int>])] = [
        ("groceries", [5411...5411, 5422...5422, 5441...5441, 5451...5451, 5462...5462, 5499...5499]),
        ("cafes", [5811...5814]),
        ("taxi", [4121...4121]),
        ("transport", [4111...4112, 4131...4131, 4784...4784, 4789...4789, 5541...5542, 5983...5983, 7523...7523]),
        ("housing", [4900...4900, 6513...6513]),
        ("telecom", [4812...4816]),
        ("subscriptions", [4899...4899, 5815...5815, 5817...5818]),
        ("health", [5047...5047, 5122...5122, 5912...5912, 5975...5976, 8011...8099]),
        ("clothes", [5137...5139, 5611...5699, 5931...5931, 5941...5941]),
        ("entertainment", [5816...5816, 5945...5945, 7829...7841, 7911...7999]),
        ("travel", [3000...3999, 4411...4411, 4511...4511, 4722...4722, 7011...7012, 7512...7512]),
        ("gifts", [5947...5947, 5992...5992]),
        ("education", [5942...5943, 8211...8299]),
    ]

    private static let mccRules: [CategoryRule] = mcc.flatMap { entry in
        entry.ranges.map { range in
            rule(entry.key, [.mccRange(range)], priority: mccPriority, name: "mcc:\(range.lowerBound)-\(range.upperBound)")
        }
    }

    // MARK: -

    /// Пространство имён для ID встроенных правил: ID одинаковы между запусками и устройствами,
    /// поэтому на правило можно сослаться из подсказки.
    private static let namespace = UUID(uuidString: "6C2F9E61-1B7A-4C3D-9F52-0E8A4D7B3C19")!

    private static func rule(_ key: String, _ conditions: [CategoryRule.Condition], priority: Int, name: String) -> CategoryRule {
        CategoryRule(
            id: CategoryRule.ID(UUID(v5: "\(key)|\(name)", namespace: namespace)),
            conditions: conditions,
            categoryID: FinanceCategory.systemID(for: key),
            priority: priority,
            origin: .builtIn
        )
    }
}
