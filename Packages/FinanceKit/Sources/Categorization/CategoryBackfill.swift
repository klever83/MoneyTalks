import Domain

/// Раскладывает по категориям уже сохранённые операции без категории.
///
/// Встроенные правила обновляются вместе с приложением, а импорт категоризирует только новые
/// операции. Без этого прошлые выписки так и остались бы «Без категории». Операции, у которых
/// пользователь сам выбрал или убрал категорию (`categoryLocked`), и переводы не трогаются.
public enum CategoryBackfill {
    /// - Returns: сколько операций получили категорию.
    @discardableResult
    public static func run(
        transactions: any TransactionRepository,
        categorizer: any TransactionCategorizer
    ) async throws -> Int {
        let pending = try await transactions.transactions(TransactionQuery())
            .filter(RuleBasedTransactionCategorizer.needsCategory)
        guard !pending.isEmpty else { return 0 }
        let categorized = try await categorizer.categorize(pending).filter { $0.categoryID != nil }
        guard !categorized.isEmpty else { return 0 }
        try await transactions.save(categorized)
        return categorized.count
    }
}
