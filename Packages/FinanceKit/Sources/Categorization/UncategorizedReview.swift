import Domain

/// Разбор операций без категории: группы по мерчанту, чтобы раскладывать их по одной группе за касание.
public enum UncategorizedReview {
    public struct Group: Identifiable, Sendable {
        public enum ID: Hashable, Sendable {
            /// Операции одного мерчанта (ключ `MerchantNormalizer.key`) с одним знаком суммы:
            /// покупки и возвраты требуют категорий разного типа.
            case merchant(key: String, isExpense: Bool)
            /// Операция без мерчанта в описании: переводы, ЕРИП, платежи из приложения банка.
            /// За что она, по выписке не видно, поэтому разбирается отдельно.
            case single(FinanceTransaction.ID)
        }

        public let id: ID
        /// Название для показа: как у самой свежей операции группы.
        public let title: String
        /// Операции группы, новые сверху.
        public let transactions: [FinanceTransaction]
        /// Суммы по валютам, сначала самая большая по модулю.
        public let totals: [Money]

        public var isExpense: Bool { transactions.first?.amount.isNegative ?? true }

        /// Для группы можно создать правило «всегда так»: у неё есть мерчант.
        public var canCreateRule: Bool {
            if case .merchant = id { true } else { false }
        }
    }

    /// Результат разбора группы: правило «всегда так», если его просили, и операции с новой категорией.
    public struct Assignment: Sendable {
        public let rule: CategoryRule?
        public let updated: [FinanceTransaction]
    }

    /// Операция ждёт категорию: без категории, не переводы, категорию не убирали вручную.
    public static func isPending(_ transaction: FinanceTransaction) -> Bool {
        RuleBasedTransactionCategorizer.needsCategory(transaction)
    }

    /// Группы операций без категории: сначала мерчанты с наибольшим числом операций,
    /// потом операции без мерчанта, новые сверху.
    public static func groups(_ transactions: [FinanceTransaction]) -> [Group] {
        let pending = transactions.filter(isPending).sorted { $0.bookedAt > $1.bookedAt }
        var order: [Group.ID] = []
        var buckets: [Group.ID: [FinanceTransaction]] = [:]
        for transaction in pending {
            let id: Group.ID = AlwaysRule.merchantKey(for: transaction)
                .map { .merchant(key: $0, isExpense: transaction.amount.isNegative) }
                ?? .single(transaction.id)
            if buckets[id] == nil { order.append(id) }
            buckets[id, default: []].append(transaction)
        }
        let groups = order.map { id in
            let items = buckets[id] ?? []
            return Group(
                id: id,
                title: items.first?.merchantNormalized ?? "",
                transactions: items,
                totals: totals(of: items)
            )
        }
        let merchants = groups.filter(\.canCreateRule).sorted { lhs, rhs in
            if lhs.transactions.count != rhs.transactions.count {
                return lhs.transactions.count > rhs.transactions.count
            }
            return magnitude(lhs) > magnitude(rhs)
        }
        return merchants + groups.filter { !$0.canCreateRule }
    }

    /// Категория для всей группы.
    ///
    /// С `always` и мерчантом получается правило «всегда так»: оно раскладывает все операции мерчанта
    /// без категории (так же, как сделает при следующем импорте), и они не закрепляются, ведь это
    /// решение правила. Без правила категория закрепляется за операциями группы как ручной выбор.
    public static func assign(
        _ group: Group,
        to categoryID: FinanceCategory.ID,
        always: Bool,
        rules: [CategoryRule],
        transactions: [FinanceTransaction]
    ) -> Assignment {
        if always, group.canCreateRule, let sample = group.transactions.first,
           let rule = AlwaysRule.make(for: sample, categoryID: categoryID, existing: rules) {
            let updated = transactions
                .filter { isPending($0) && rule.matches($0) }
                .map { transaction in
                    var transaction = transaction
                    transaction.categoryID = categoryID
                    return transaction
                }
            return Assignment(rule: rule, updated: updated)
        }
        let updated = group.transactions.map { transaction in
            var transaction = transaction
            transaction.categoryID = categoryID
            transaction.categoryLocked = true
            return transaction
        }
        return Assignment(rule: nil, updated: updated)
    }

    private static func totals(of transactions: [FinanceTransaction]) -> [Money] {
        Dictionary(grouping: transactions, by: \.amount.currency)
            .map { currency, items in
                Money(minorUnits: items.reduce(0) { $0 + $1.amount.minorUnits }, currency: currency)
            }
            .sorted { abs($0.minorUnits) > abs($1.minorUnits) }
    }

    private static func magnitude(_ group: Group) -> Int64 {
        group.totals.first.map { abs($0.minorUnits) } ?? 0
    }
}
