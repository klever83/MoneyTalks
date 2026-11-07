import Domain

/// Категоризация по правилам пользователя и встроенным правилам.
/// Правила читаются при каждом вызове: новое правило пользователя сразу действует на следующий импорт.
/// Если передан репозиторий категорий, правила, ведущие в скрытые или удалённые категории, пропускаются.
public struct RuleBasedTransactionCategorizer: TransactionCategorizer {
    private let repository: any CategoryRuleRepository
    private let categories: (any CategoryRepository)?
    private let builtIn: [CategoryRule]

    public init(
        repository: any CategoryRuleRepository,
        categories: (any CategoryRepository)? = nil,
        builtIn: [CategoryRule] = BuiltInRules.all
    ) {
        self.repository = repository
        self.categories = categories
        self.builtIn = builtIn
    }

    public func categorize(_ transactions: [FinanceTransaction]) async throws -> [FinanceTransaction] {
        guard transactions.contains(where: Self.needsCategory) else { return transactions }
        var rules = try await repository.rules() + builtIn
        if let categories {
            let available = Set(try await categories.categories().filter { !$0.isHidden }.map(\.id))
            rules = rules.filter { available.contains($0.categoryID) }
        }
        return RuleCategorizer(rules: rules).apply(to: transactions)
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
