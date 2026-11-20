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
        var categories: [FinanceTransaction.ID: FinanceCategory.ID] = [:]
        for transaction in try await categorizer.categorize(pending) {
            if let categoryID = transaction.categoryID { categories[transaction.id] = categoryID }
        }
        // Только категория и только у тех, кто её всё ещё ждёт: раскладка идёт при запуске,
        // и пользователь может в это время править операции.
        return try await transactions.fillCategories(categories)
    }
}
