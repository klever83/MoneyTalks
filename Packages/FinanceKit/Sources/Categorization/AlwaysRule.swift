import Domain

/// Правило «всегда так»: после ручной смены категории операции её мерчант всегда получает эту категорию.
public enum AlwaysRule {
    /// Правило для мерчанта операции. Если у пользователя уже есть правило «всегда так» для этого мерчанта,
    /// оно обновляется (тот же ID), а не дублируется. `nil`, если у операции нет мерчанта: у P2P, ЕРИП
    /// и переводов ключ после удаления служебных слов пустой, и одно «всегда так» на переводе другу
    /// отправило бы в эту категорию все такие операции.
    public static func make(
        for transaction: FinanceTransaction,
        categoryID: FinanceCategory.ID,
        existing: [CategoryRule]
    ) -> CategoryRule? {
        guard let key = merchantKey(for: transaction) else { return nil }
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

    /// Ключ мерчанта операции для правила или `nil`, если мерчанта в описании нет.
    public static func merchantKey(for transaction: FinanceTransaction) -> String? {
        // Стоп-лист служебных слов не бывает полным («Перевод на карту другого банка» даёт ключ
        // «другого банка»), поэтому на всём, что похоже на перевод, «всегда так» не предлагается.
        guard !TransferWords.appear(in: transaction.merchantRaw) else { return nil }
        let key = MerchantNormalizer.key(transaction.merchantRaw)
        guard !key.isEmpty, !channelKeys.contains(key) else { return nil }
        return key
    }

    /// Ключи каналов, а не мерчантов: платежи из приложения или интернет-банка (у Приорбанка
    /// «MOBILE BANK») бывают за что угодно, и одно правило на них разложило бы все такие платежи в одну категорию.
    static let channelKeys: Set<String> = [
        "mobile", "mobile banking", "internet", "internet banking", "sms",
        "мобильный", "мобильный банк", "интернет", "интернет банк", "интернет банкинг",
    ]

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
