import Domain

/// Разбор операций без категории: группы по мерчанту, чтобы раскладывать их по одной группе за касание.
public enum UncategorizedReview {
    public struct Group: Identifiable, Sendable {
        public enum ID: Hashable, Sendable {
            /// Операции одного мерчанта (ключ `MerchantNormalizer.key`), покупки вместе с возвратами.
            case merchant(String)
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
        /// Категории расходов, а не доходов. У мерчанта с покупками (среди всех операций, не только
        /// ожидающих) и возвраты получают категорию расходов: возврат в «Кафе» уменьшает расход на кафе,
        /// так их считает аналитика и так раскладывает правило мерчанта при импорте.
        public let isExpense: Bool

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
    /// - Parameter transactions: все операции: по ним видно, есть ли у мерчанта покупки.
    public static func groups(_ transactions: [FinanceTransaction]) -> [Group] {
        let pending = transactions.filter(isPending).sorted { $0.bookedAt > $1.bookedAt }
        var order: [Group.ID] = []
        var buckets: [Group.ID: [FinanceTransaction]] = [:]
        for transaction in pending {
            let id: Group.ID = AlwaysRule.merchantKey(for: transaction).map { .merchant($0) } ?? .single(transaction.id)
            if buckets[id] == nil { order.append(id) }
            buckets[id, default: []].append(transaction)
        }
        let pendingKeys = Set(order.compactMap { id -> String? in
            if case .merchant(let key) = id { key } else { nil }
        })
        let keysWithPurchases = Set(transactions.compactMap { transaction -> String? in
            guard transaction.amount.isNegative, transaction.kind != .transfer, transaction.deletedAt == nil else { return nil }
            let key = MerchantNormalizer.key(transaction.merchantRaw)
            return pendingKeys.contains(key) ? key : nil
        })
        let groups = order.map { id in
            let items = buckets[id] ?? []
            let isExpense: Bool = switch id {
            case .merchant(let key): keysWithPurchases.contains(key)
            case .single: items.first?.amount.isNegative ?? true
            }
            return Group(
                id: id,
                title: items.first?.merchantNormalized ?? "",
                transactions: items,
                totals: totals(of: items),
                isExpense: isExpense
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
    /// С `always` и мерчантом получается правило «всегда так» для мерчанта, а операции группы
    /// (это все его операции без категории) не закрепляются: так же их разложит правило при импорте.
    /// У мерчанта без покупок правило только для поступлений: доходная категория не должна
    /// достаться будущим покупкам. Без правила категория закрепляется за операциями группы как ручной выбор.
    public static func assign(
        _ group: Group,
        to categoryID: FinanceCategory.ID,
        always: Bool,
        rules: [CategoryRule]
    ) -> Assignment {
        if always, group.canCreateRule, let rule = rule(for: group, categoryID: categoryID, existing: rules) {
            return Assignment(rule: rule, updated: group.transactions.map { transaction in
                var transaction = transaction
                transaction.categoryID = categoryID
                return transaction
            })
        }
        return Assignment(rule: nil, updated: group.transactions.map { transaction in
            var transaction = transaction
            transaction.categoryID = categoryID
            transaction.categoryLocked = true
            return transaction
        })
    }

    private static func rule(for group: Group, categoryID: FinanceCategory.ID, existing: [CategoryRule]) -> CategoryRule? {
        guard let sample = group.transactions.first,
              var rule = AlwaysRule.make(for: sample, categoryID: categoryID, existing: existing) else { return nil }
        guard !group.isExpense else { return rule }
        rule.conditions.append(.amountSign(.positive))
        let previous = existing.first { $0.origin == .user && $0.conditions == rule.conditions }
        rule.id = previous?.id ?? CategoryRule.ID()
        rule.priority = previous?.priority ?? 0
        return rule
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
