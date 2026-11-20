import Domain
import Foundation

/// Встроенные правила: популярные мерчанты Беларуси, диапазоны MCC и общие слова в названиях.
///
/// Живут в коде, а не в базе: обновляются вместе с приложением. Правила пользователя
/// всегда важнее (`RuleCategorizer`), а внутри встроенных мерчант важнее MCC, MCC важнее
/// общего слова («KAFE», «AZS»): у части банков (Приорбанк) MCC в выписке нет, и для них
/// остаются только названия.
/// Среди правил одного приоритета побеждает самое длинное совпадение (`RuleCategorizer`):
/// «SILVER SCREEN GREEN CITY» — кино, а не продукты по слову GREEN.
/// Категории — системные, по `systemKey`: их ID одинаковы на всех устройствах.
public enum BuiltInRules {
    static let merchantPriority = 100
    static let mccPriority = 50
    static let keywordPriority = 40

    /// Версия набора правил. Увеличивается при каждом изменении: после обновления приложения
    /// уже загруженные операции без категории раскладываются заново (`CategoryBackfill`).
    public static let version = 4

    public static let all: [CategoryRule] = merchantRules + mccRules + keywordRules

    // MARK: - Мерчанты

    /// Подстроки достаточно длинные, чтобы не совпасть случайно; короткие названия — отдельным словом.
    /// В выписках Приорбанка кавычки заменены дефисами («KAFE -GOLFSTRIM-»), названия обрезаны
    /// примерно до 25 символов, а перенос строки может вставить пробел внутрь слова («WWW.PASS.R W.BY»):
    /// поэтому у части мерчантов несколько вариантов написания.
    private static let merchants: [(key: String, contains: [String], words: [String])] = [
        ("groceries", [
            "EVROOPT", "ЕВРООПТ", "GIPPO", "ГИППО", "KORONA", "КОРОНА",
            "BELMARKET", "БЕЛМАРКЕТ", "RUBLEVSKIY", "РУБЛЕВСКИЙ", "SOSEDI", "СОСЕДИ",
            "VITALUR", "ВИТАЛЮР", "GROSHYK", "ГРОШЫК", "HIT DISKONT", "ХИТ ДИСКОНТ", "MART INN",
            "SEM PYATNITS", "7PYATNITS", "KOPEECHKA", "КОПЕЕЧКА", "PROSTORE", "MARTSIN", "МАРЦИН",
            "DVA GUSYA", "ДВА ГУСЯ", "7-ELEVEN", "WAITROSE", "REALPRODTORG",
        ], ["SANTA", "САНТА", "GREEN", "ГРИН", "ALMI", "АЛМИ", "SPAR"]),
        ("cafes", [
            "MCDONALD", "МАКДОНАЛДС", "BURGER KING", "VKUSNO I TOCHKA", "ВКУСНО И ТОЧКА",
            "STARBUCKS", "COFFEE", "КОФЕЙНЯ", "KOFEYNYA", "PAPA JOHNS", "DOMINOS",
            "DODO PIZZA", "DODOPIZZA", "ДОДО ПИЦЦА",
            "YANDEX.EDA", "YANDEX EDA", "YANDEXEDA", "ЯНДЕКС ЕДА", "JUST-EAT", "JUSTEAT", "DELIVIO",
            "GOLFSTRIM", "BATSKI", "RESTORAN BYSTROGO", "RESTORAN PBO", "SALATEIRA", "PIVOVAR",
            "LAPASTERIYA", "BURGERLAB", "KHINKALNYA", "HINKALNYA", "ХИНКАЛЬНАЯ", "ELEMENTUM",
            // Бар сети «7 пятниц»: длиннее, чем магазины сети «7PYATNITS» в продуктах, поэтому важнее.
            "BAR -7PYATNITS",
        ], ["KFC", "LIDO", "ЛИДО", "SUBWAY"]),
        ("taxi", [
            "YANDEX GO", "YANDEX*GO", "YANDEX.GO", "YANDEX.TAXI", "ЯНДЕКС GO", "ЯНДЕКС ТАКСИ",
            "TAXI", "ТАКСИ",
        ], ["UBER", "BOLT", "FASTEN", "ФАСТЕН"]),
        ("transport", [
            "BELARUSNEFT", "БЕЛОРУСНЕФТЬ", "LUKOIL", "ЛУКОЙЛ", "GAZPROMNEFT", "ГАЗПРОМНЕФТЬ",
            "METROPOLITEN", "МЕТРОПОЛИТЕН", "BELZHD", "BELARUSKAYA ZHELEZNAYA", "БЕЛОРУССКАЯ ЖЕЛЕЗНАЯ",
            "PASS.RW.BY", "PASS.R W.BY", "PASS.RW .BY", "PASS.RW.B Y",
        ], ["A-100", "БЖД"]),
        ("housing", [
            "ЖКХ", "ЖЭС", "КОММУНАЛ", "МИНСКЭНЕРГО", "ЭНЕРГОСБЫТ", "ВОДОКАНАЛ", "ГОРГАЗ", "ОБЛГАЗ",
            "MINSKENERGO", "VODOKANAL",
        ], []),
        ("telecom", [
            "BELTELECOM", "БЕЛТЕЛЕКОМ", "BYFLY", "LIFE:)",
        ], ["MTS", "МТС", "A1", "ZALA"]),
        ("health", [
            "APTEKA", "АПТЕКА", "PHARMACY", "БЕЛФАРМАЦИЯ", "BELFARMACIYA",
            "СТОМАТОЛОГ", "STOMATOLOG", "МЕДЦЕНТР", "MEDCENTR", "HELIX", "SYNLAB", "SINLAB", "INVITRO",
        ], ["LODE", "ЛОДЭ"]),
        ("clothes", [
            "LC WAIKIKI", "MARK FORMEL", "МАРК ФОРМЭЛЬ", "MILAVITSA", "МИЛАВИЦА",
            "BELWEST", "БЕЛВЕСТ", "SPORTMASTER", "СПОРТМАСТЕР", "RESERVED", "BERSHKA", "PULL&BEAR",
            "PULL AND BEAR", "STRADIVARIUS", "MASSIMO DUTTI",
        ], ["ZARA", "H&M"]),
        ("subscriptions", [
            "NETFLIX", "SPOTIFY", "APPLE.COM/BILL", "ICLOUD", "YOUTUBE",
            "YANDEX PLUS", "YANDEX.PLUS", "YANDEXPLUS", "ЯНДЕКС ПЛЮС",
            "KINOPOISK", "КИНОПОИСК", "OPENAI", "CHATGPT", "VDSINA",
        ], ["OKKO", "IVI"]),
        ("entertainment", [
            "SILVER SCREEN", "MOOON", "KINOTEATR", "КИНОТЕАТР", "STEAMGAMES", "STEAM PURCHASE",
            "PLAYSTATION", "BILETY", "TICKETPRO", "BEZKASSIRA", "24AFISHA", "KVITKI", "KARTING", "MUSEUM",
        ], []),
        ("travel", [
            "BOOKING.COM", "AIRBNB", "BELAVIA", "БЕЛАВИА", "AVIASALES", "RYANAIR", "WIZZ AIR", "WIZZAIR",
            "UCUZABILET", "AGODA", "TOURISM",
        ], []),
        ("education", [
            "COURSERA", "UDEMY", "SKILLBOX", "DUOLINGO",
        ], []),
        ("marketplaces", [
            "WILDBERRIES", "LAMODA", "ALIEXPRESS", "21VEK", "21 VEK", "KUFAR",
        ], ["OZON", "ОЗОН"]),
        ("beauty", [
            "ZOLOTOE YABLOKO", "GOLDAPPLE", "ЗОЛОТОЕ ЯБЛОКО", "PERFUMES", "COSMETICS", "KOSMETIKA", "КОСМЕТИКА",
            "LETUAL", "ЛЭТУАЛЬ", "SALON KRASOTY", "САЛОН КРАСОТЫ", "BARBERSHOP", "PARIKMAKHER", "ПАРИКМАХЕР",
        ], ["MILA", "МИЛА"]),
        ("sport", [
            "PRIME GYM", "PRAYM DZHIM", "FITNES", "ФИТНЕС", "TOURISTSHOP", "DECATHLON",
        ], []),
        ("home", [
            "FIX PRICE", "FIXPRICE", "ФИКС ПРАЙС", "IKEA", "JYSK", "ЮСК",
        ], ["OMA", "ОМА", "MILE", "МАЙЛ"]),
        ("electronics", [
            "ZEON", "ELEKTRONIKA", "ЭЛЕКТРОНИКА", "5 ELEMENT", "5ELEMENT", "5 ЭЛЕМЕНТ", "ELECTROSILA", "ЭЛЕКТРОСИЛА",
        ], ["DNS"]),
        ("betting", [
            "PARIMATCH", "FONBET", "BETERA", "BIZONBET", "MAXLINE", "BETCITY",
        ], ["PM.BY"]),
        ("gifts", [
            "BUKETNAYA", "ЦВЕТЫ",
        ], ["FLOWER", "FLOWERS"]),
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
        // Зарплата: только поступления. «Зачисление по ведомости» — зарплата в выписке по счёту Приорбанка.
        for text in ["ЗАРАБОТН", "ЗАРПЛАТ", "SALARY", "ПО ВЕДОМОСТИ"] {
            rules.append(rule("salary", [.merchantContains(text), .amountSign(.positive)], priority: merchantPriority, name: "salary:\(text)"))
        }
        // Проценты банка по остатку и вкладам.
        for text in ["ПРОЦЕНТ", "КАПИТАЛИЗАЦИЯ"] {
            rules.append(rule("interest", [.merchantContains(text), .amountSign(.positive)], priority: merchantPriority, name: "interest:\(text)"))
        }
        // Комиссии банка: только списания («Комиссионное вознаграждение» в плюс — это кэшбэк).
        for text in ["УСЛУГ БАНКА", "КОМИССИЯ"] {
            rules.append(rule("fees", [.merchantContains(text), .amountSign(.negative)], priority: merchantPriority, name: "fees:\(text)"))
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
        ("groceries", [5921...5921]),
        ("marketplaces", [5262...5262]),
        ("beauty", [5977...5977, 7230...7230, 7297...7298]),
        ("home", [5200...5200, 5211...5211, 5251...5251, 5712...5712, 5719...5719]),
        ("electronics", [5045...5045, 5732...5732]),
    ]

    private static let mccRules: [CategoryRule] = mcc.flatMap { entry in
        entry.ranges.map { range in
            rule(entry.key, [.mccRange(range)], priority: mccPriority, name: "mcc:\(range.lowerBound)-\(range.upperBound)")
        }
    }

    // MARK: - Общие слова

    /// Слова, по которым видно тип места, если сам мерчант неизвестен: «KAFE -ZVEZDA-», «AZS N20».
    /// Только отдельным словом: «BAR» не находится в «BARS», «PIZZA» — в «PIZZALAND».
    private static let keywords: [(key: String, words: [String])] = [
        ("cafes", [
            "KAFE", "CAFE", "КАФЕ", "MINI-KAFE", "RESTORAN", "RESTAURANT", "РЕСТОРАН", "REST.", "BAR", "БАР",
            "GASTROBAR", "PIZZA", "PIZZERIA", "PIZZERIYA", "PITSTSERIYA", "ПИЦЦЕРИЯ", "SUSHI", "СУШИ",
            "BUFET", "БУФЕТ", "STOLOVAYA", "СТОЛОВАЯ", "BURGER", "KONDITERSKAYA",
        ]),
        ("groceries", [
            "SUPERMARKET", "СУПЕРМАРКЕТ", "UNIVERSAM", "УНИВЕРСАМ", "GASTRONOM", "ГАСТРОНОМ", "PRODUKTY", "ПРОДУКТЫ",
            "KONDITERSKIY",
        ]),
        ("transport", ["AZS", "AAZS", "MAZS", "АЗС"]),
        ("health", ["DENT", "KLINIKA", "КЛИНИКА", "MEDICAL"]),
        ("travel", ["HOTEL", "ОТЕЛЬ", "HOSTEL", "ХОСТЕЛ", "SUITES", "AIRLINES"]),
        ("sport", ["GYM"]),
        ("beauty", ["MANIKYUR", "МАНИКЮР", "NAIL", "SPA", "BROW", "BROWS", "LASH"]),
    ]

    private static let keywordRules: [CategoryRule] = keywords.flatMap { entry in
        entry.words.map { word in
            rule(entry.key, [.merchantWord(word)], priority: keywordPriority, name: "keyword:\(word)")
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
