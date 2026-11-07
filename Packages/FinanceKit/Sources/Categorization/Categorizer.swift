import Domain

public struct CategorySuggestion: Hashable, Sendable {
    public var categoryID: FinanceCategory.ID
    public var ruleID: CategoryRule.ID?
    /// 1 — правило пользователя, меньше — встроенные правила и, позже, ML-модель.
    public var confidence: Double

    public init(categoryID: FinanceCategory.ID, ruleID: CategoryRule.ID?, confidence: Double) {
        self.categoryID = categoryID
        self.ruleID = ruleID
        self.confidence = confidence
    }
}

/// Подсказывает категорию для операции. Позже за этим протоколом встанет цепочка
/// «правила → Core ML-модель → общий словарь мерчантов».
public protocol Categorizer: Sendable {
    func suggest(for transaction: FinanceTransaction) -> CategorySuggestion?
}

/// Детерминированный движок правил: правила пользователя, затем встроенные; внутри — по приоритету,
/// а среди равных по приоритету — более конкретное (длиннее текст мерчанта) раньше.
public struct RuleCategorizer: Categorizer {
    public let rules: [CategoryRule]

    public init(rules: [CategoryRule]) {
        self.rules = rules.sorted { lhs, rhs in
            (lhs.origin.order, -lhs.priority, -lhs.specificity) < (rhs.origin.order, -rhs.priority, -rhs.specificity)
        }
    }

    public func suggest(for transaction: FinanceTransaction) -> CategorySuggestion? {
        var cachedKey: String?
        let merchantKey: () -> String = {
            if let cachedKey { return cachedKey }
            let key = MerchantNormalizer.key(transaction.merchantRaw)
            cachedKey = key
            return key
        }
        guard let rule = rules.first(where: { $0.matches(transaction, merchantKey: merchantKey) }) else { return nil }
        return CategorySuggestion(
            categoryID: rule.categoryID,
            ruleID: rule.id,
            confidence: rule.origin == .user ? 1 : 0.8
        )
    }
}

private extension CategoryRule {
    /// Длина текста условий по мерчанту: чем длиннее совпадение, тем точнее правило.
    var specificity: Int {
        conditions.reduce(0) { total, condition in
            switch condition {
            case .merchantContains(let text), .merchantEquals(let text), .merchantWord(let text), .merchantKey(let text):
                total + text.count
            case .mccRange, .amountSign, .account:
                total
            }
        }
    }
}

private extension CategoryRule.Origin {
    var order: Int {
        switch self {
        case .user: 0
        case .builtIn: 1
        }
    }
}
