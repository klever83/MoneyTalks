import Domain

/// Правило «всегда так»: после ручной смены категории операции её мерчант всегда получает эту категорию.
public enum AlwaysRule {
    /// Правило для мерчанта операции. Если у пользователя уже есть правило «всегда так» для этого мерчанта,
    /// оно обновляется (тот же ID), а не дублируется. `nil`, если у операции нет осмысленного мерчанта.
    public static func make(
        for transaction: FinanceTransaction,
        categoryID: FinanceCategory.ID,
        existing: [CategoryRule]
    ) -> CategoryRule? {
        let key = MerchantNormalizer.key(transaction.merchantRaw)
        guard !key.isEmpty else { return nil }
        let condition = CategoryRule.Condition.merchantKey(key)
        let previous = existing.first { $0.origin == .user && $0.conditions == [condition] }
        return CategoryRule(
            id: previous?.id ?? CategoryRule.ID(),
            conditions: [condition],
            categoryID: categoryID,
            priority: previous?.priority ?? 0,
            origin: .user
        )
    }

    /// Прошлые операции, которым правило поменяет категорию: подходят под правило, не переводы,
    /// категория не закреплена вручную и отличается от категории правила.
    public static func affected(by rule: CategoryRule, in transactions: [FinanceTransaction]) -> [FinanceTransaction] {
        transactions.filter { transaction in
            transaction.deletedAt == nil
                && transaction.kind != .transfer
                && !transaction.categoryLocked
                && transaction.categoryID != rule.categoryID
                && rule.matches(transaction)
        }
    }
}
