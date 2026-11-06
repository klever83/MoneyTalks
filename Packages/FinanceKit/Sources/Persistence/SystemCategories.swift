import Domain

/// Категории, которые создаются при первом запуске. Названия локализуются по `systemKey`.
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
    ]

    private static func expense(_ key: String, _ name: String, _ image: String, _ color: String) -> FinanceCategory {
        FinanceCategory(name: name, systemKey: key, systemImage: image, colorHex: color, kind: .expense)
    }

    private static func income(_ key: String, _ name: String, _ image: String, _ color: String) -> FinanceCategory {
        FinanceCategory(name: name, systemKey: key, systemImage: image, colorHex: color, kind: .income)
    }
}
