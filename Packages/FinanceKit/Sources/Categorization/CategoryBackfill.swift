import Domain

/// Раскладывает по категориям уже сохранённые операции без категории.
///
/// Встроенные правила обновляются вместе с приложением, а импорт категоризирует только новые
/// операции. Без этого прошлые выписки так и остались бы «Без категории». Операции, у которых
/// пользователь сам выбрал или убрал категорию (`categoryLocked`), и переводы не трогаются.
public enum CategoryBackfill {
    /// Переводы на свой счёт, которые банк так и назвал (`OwnTransfers`), становятся переводом.
    /// - Returns: сколько операций получили категорию или стали переводом.
    @discardableResult
    public static func run(
        transactions: any TransactionRepository,
        categorizer: any TransactionCategorizer
    ) async throws -> Int {
        let pending = try await transactions.transactions(TransactionQuery())
            .filter(RuleBasedTransactionCategorizer.needsCategory)
        guard !pending.isEmpty else { return 0 }
        // Переводы на свой счёт без второй стороны: не расход, категория им не нужна.
        let own = pending.filter(OwnTransfers.shouldMark)
        let marked = try await transactions.markTransfers(own.map(\.id))
        let ownIDs = Set(own.map(\.id))
        var categories: [FinanceTransaction.ID: FinanceCategory.ID] = [:]
        for transaction in try await categorizer.categorize(pending.filter { !ownIDs.contains($0.id) }) {
            if let categoryID = transaction.categoryID { categories[transaction.id] = categoryID }
        }
        // Только категория и только у тех, кто её всё ещё ждёт: раскладка идёт при запуске,
        // и пользователь может в это время править операции.
        return try await marked + transactions.fillCategories(categories)
    }
}
