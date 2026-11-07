import Domain

/// Категоризация по правилам пользователя и встроенным правилам.
/// Правила читаются при каждом вызове: новое правило пользователя сразу действует на следующий импорт.
public struct RuleBasedTransactionCategorizer: TransactionCategorizer {
    private let repository: any CategoryRuleRepository
    private let builtIn: [CategoryRule]

    public init(repository: any CategoryRuleRepository, builtIn: [CategoryRule] = BuiltInRules.all) {
        self.repository = repository
        self.builtIn = builtIn
    }

    public func categorize(_ transactions: [FinanceTransaction]) async throws -> [FinanceTransaction] {
        guard transactions.contains(where: Self.needsCategory) else { return transactions }
        let categorizer = RuleCategorizer(rules: try await repository.rules() + builtIn)
        return categorizer.apply(to: transactions)
    }

    static func needsCategory(_ transaction: FinanceTransaction) -> Bool {
        transaction.categoryID == nil
            && !transaction.categoryLocked
            && transaction.kind != .transfer
            && transaction.deletedAt == nil
    }
}

public extension RuleCategorizer {
    /// Проставляет подсказанные категории операциям без категории (см. `TransactionCategorizer`).
    func apply(to transactions: [FinanceTransaction]) -> [FinanceTransaction] {
        transactions.map { transaction in
            guard RuleBasedTransactionCategorizer.needsCategory(transaction),
                  let suggestion = suggest(for: transaction) else { return transaction }
            var categorized = transaction
            categorized.categoryID = suggestion.categoryID
            return categorized
        }
    }
}
