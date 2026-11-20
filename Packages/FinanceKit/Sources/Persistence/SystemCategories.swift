import Domain

/// Категории, которые создаются при первом запуске. Названия локализуются по `systemKey`,
/// ID детерминированы (`FinanceCategory.systemID(for:)`) и совпадают на всех устройствах.
enum SystemCategories {
    static let all: [FinanceCategory] = [
        expense("groceries", "Продукты", "cart", "#34C759"),
        expense("cafes", "Кафе и рестораны", "fork.knife", "#FF9500"),
        expense("transport", "Транспорт", "bus", "#007AFF"),
        expense("taxi", "Такси", "car", "#FFCC00"),
        expense("housing", "Жильё и коммуналка", "house", "#AF52DE"),
        expense("telecom", "Связь и интернет", "antenna.radiowaves.left.and.right", "#5AC8FA"),
        expense("health", "Здоровье", "cross.case", "#FF2D55"),
        expense("clothes", "Одежда и обувь", "tshirt", "#FF6482"),
        expense("entertainment", "Развлечения", "gamecontroller", "#5856D6"),
        expense("subscriptions", "Подписки", "repeat", "#64D2FF"),
        expense("travel", "Путешествия", "airplane", "#30B0C7"),
        expense("gifts", "Подарки", "gift", "#FF3B30"),
        expense("education", "Образование", "book", "#A2845E"),
        expense("other", "Другое", "ellipsis.circle", "#8E8E93"),
        income("salary", "Зарплата", "banknote", "#34C759"),
        income("other_income", "Прочие доходы", "plus.circle", "#30D158"),
    ] + added + addedV10

    /// Категории, добавленные после первой версии: у установленных приложений их создаёт
    /// миграция `v9-more-system-categories`, у новых — та же `v1-system-categories`.
    ///
    /// Сюда больше ничего не дописывать: кто уже прошёл v9, новую категорию не получит,
    /// а правило с ней молча не сработает. Следующие системные категории — отдельным списком
    /// со своей миграцией (`v10-…`) и с тестом в `SystemCategoriesMigrationTests`.
    static let added: [FinanceCategory] = [
        expense("marketplaces", "Маркетплейсы", "shippingbox", "#FF9F0A"),
        expense("beauty", "Красота и уход", "sparkles", "#BF5AF2"),
        expense("sport", "Спорт", "figure.run", "#32D74B"),
        expense("home", "Дом и хозтовары", "sofa", "#AC8E68"),
        expense("electronics", "Электроника", "desktopcomputer", "#0A84FF"),
        expense("betting", "Ставки и лотереи", "dice", "#FF453A"),
        expense("fees", "Комиссии банка", "building.columns", "#636366"),
        income("interest", "Проценты", "percent", "#66D4CF"),
    ]

    /// Категории миграции `v10-transfers-to-people`: деньги другим людям (P2P, MOBILE BANK)
    /// считаются расходом, но отдельно от покупок. Список тоже заморожен, как `added`.
    static let addedV10: [FinanceCategory] = [
        expense("transfers_people", "Переводы людям", "person.2", "#5E5CE6"),
    ]

    private static func expense(_ key: String, _ name: String, _ image: String, _ color: String) -> FinanceCategory {
        FinanceCategory(
            id: FinanceCategory.systemID(for: key),
            name: name, systemKey: key, systemImage: image, colorHex: color, kind: .expense
        )
    }

    private static func income(_ key: String, _ name: String, _ image: String, _ color: String) -> FinanceCategory {
        FinanceCategory(
            id: FinanceCategory.systemID(for: key),
            name: name, systemKey: key, systemImage: image, colorHex: color, kind: .income
        )
    }
}
