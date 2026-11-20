import Domain
import Foundation

/// Анкета после импорта: короткая очередь вопросов «что это за место?» по одному мерчанту,
/// самые крупные траты первыми. Каждый ответ становится правилом «всегда так»
/// (`UncategorizedReview.assign`), поэтому один и тот же мерчант не спрашивается дважды.
public enum QuickReview {
    /// Сколько вопросов за один заход: дольше минуты анкету не проходят.
    public static let defaultLimit = 20
    /// На сколько «Не знаю» убирает мерчанта из анкеты. На экране «Без категории» он остаётся.
    public static let snoozeInterval: TimeInterval = 30 * 24 * 3600

    /// Мерчанты для анкеты: только расходы (по ним считается Обзор), без отложенных «Не знаю»,
    /// сначала самые крупные по сумме.
    /// - Parameter snoozedUntil: ключ мерчанта → до какого момента не спрашивать.
    public static func queue(
        _ groups: [UncategorizedReview.Group],
        snoozedUntil: [String: Date] = [:],
        now: Date = .now,
        limit: Int = defaultLimit
    ) -> [UncategorizedReview.Group] {
        let candidates = groups.filter { group in
            guard group.isExpense, case .merchant(let key) = group.id else { return false }
            return (snoozedUntil[key] ?? .distantPast) <= now
        }
        return Array(candidates.sorted { magnitude($0) > magnitude($1) }.prefix(limit))
    }

    // MARK: - Платежи через приложение банка

    /// Операции без категории, у которых вместо мерчанта канал платежа: у Приорбанка «MOBILE BANK».
    /// Про них спрашивается один раз сразу обо всех: обычно это переводы.
    public struct ChannelGroup: Identifiable, Sendable {
        public let id: String
        /// Название для показа: как у самой свежей операции.
        public let title: String
        /// Операции, новые сверху.
        public let transactions: [FinanceTransaction]
        public let totals: [Money]
    }

    /// Расходы без категории через канал платежа, по одному на канал, самые крупные первыми.
    public static func channelGroups(_ transactions: [FinanceTransaction]) -> [ChannelGroup] {
        let pending = transactions
            .filter { UncategorizedReview.isPending($0) && $0.amount.isNegative }
            .sorted { $0.bookedAt > $1.bookedAt }
        let byKey = Dictionary(grouping: pending) { MerchantNormalizer.key($0.merchantRaw) }
        return byKey
            .filter { AlwaysRule.channelKeys.contains($0.key) }
            .map { key, items in
                ChannelGroup(id: key, title: items.first?.merchantNormalized ?? key, transactions: items, totals: totals(of: items))
            }
            .sorted { abs($0.totals.first?.minorUnits ?? 0) > abs($1.totals.first?.minorUnits ?? 0) }
    }

    /// «Это переводы на свои карты»: операции становятся переводами и уходят из доходов и расходов.
    public static func markAsTransfers(_ group: ChannelGroup) -> [FinanceTransaction] {
        group.transactions.map { transaction in
            var transaction = transaction
            transaction.kind = .transfer
            transaction.categoryID = nil
            return transaction
        }
    }

    /// «Это не перевод»: отменяет отметку перевода у операции без пары, например после ответа
    /// «Переводы на свои карты» в анкете. Тип снова по знаку суммы, категория снимается вместе
    /// с закреплением, чтобы операция вернулась в «Без категории» и её снова разложили правила.
    /// `nil`, если это не перевод или у перевода есть вторая сторона на другом своём счёте:
    /// такую пару отменяют вместе, а не по одной операции.
    public static func undoTransfer(_ transaction: FinanceTransaction) -> FinanceTransaction? {
        guard transaction.kind == .transfer, transaction.transferPairID == nil else { return nil }
        var transaction = transaction
        transaction.kind = transaction.amount.isNegative ? .expense : .income
        transaction.categoryID = nil
        transaction.categoryLocked = false
        return transaction
    }

    /// «Это переводы другим людям» и т. п.: категория закрепляется за всеми операциями канала.
    /// Правила нет: следующие платежи через приложение могут быть за что угодно.
    public static func assign(_ group: ChannelGroup, to categoryID: FinanceCategory.ID) -> [FinanceTransaction] {
        group.transactions.map { transaction in
            var transaction = transaction
            transaction.categoryID = categoryID
            transaction.categoryLocked = true
            return transaction
        }
    }

    // MARK: - Подсказки

    /// Всё, что нужно подсказкам, собранное за один проход по операциям: на каждой карточке анкеты
    /// пересчитывать ключи мерчантов десятков тысяч операций слишком дорого.
    public struct SuggestionIndex: Sendable {
        /// Операции по ключу мерчанта, без удалённых и переводов.
        let byMerchant: [String: [FinanceTransaction]]
        /// Категории расходов по числу операций, самые частые первыми.
        let frequentExpense: [FinanceCategory.ID]
        /// Категории поступлений по числу операций, самые частые первыми.
        let frequentIncome: [FinanceCategory.ID]

        public init(_ transactions: [FinanceTransaction]) {
            let live = transactions.filter { $0.deletedAt == nil && $0.kind != .transfer }
            byMerchant = Dictionary(grouping: live) { MerchantNormalizer.key($0.merchantRaw) }
            frequentExpense = Self.frequent(live.filter(\.amount.isNegative))
            frequentIncome = Self.frequent(live.filter { !$0.amount.isNegative })
        }

        /// Категории по числу операций, самые частые первыми.
        private static func frequent(_ transactions: [FinanceTransaction]) -> [FinanceCategory.ID] {
            Dictionary(grouping: transactions.compactMap(\.categoryID)) { $0 }
                .sorted { $0.value.count > $1.value.count }
                .map(\.key)
        }
    }

    /// Варианты ответа для мерчанта, лучшие первыми, не больше `limit`:
    /// 1. категория, которую тот же мерчант уже получил в другой операции (например, по MCC в выписке
    ///    другого банка, где код есть);
    /// 2. категория по MCC, если он есть у какой-то операции мерчанта;
    /// 3. самые частые категории пользователя того же типа.
    /// - Parameter categories: категории, которые можно предлагать (видимые, нужного типа).
    public static func suggestions(
        for group: UncategorizedReview.Group,
        index: SuggestionIndex,
        categories: [FinanceCategory],
        limit: Int = 5
    ) -> [FinanceCategory.ID] {
        let allowed = Set(categories.map(\.id))
        var result: [FinanceCategory.ID] = []
        func add(_ id: FinanceCategory.ID?) {
            guard let id, allowed.contains(id), !result.contains(id), result.count < limit else { return }
            result.append(id)
        }

        let frequent = group.isExpense ? index.frequentExpense : index.frequentIncome
        guard case .merchant(let key) = group.id else {
            frequent.forEach(add)
            return result
        }
        let sameMerchant = index.byMerchant[key] ?? []
        // 1. Тот же мерчант уже разложен в другой операции.
        let known = Dictionary(grouping: sameMerchant.compactMap(\.categoryID)) { $0 }
        known.sorted { $0.value.count > $1.value.count }.forEach { add($0.key) }
        // 2. MCC из операции, где он есть.
        let byMCC = RuleCategorizer(rules: BuiltInRules.all)
        for transaction in sameMerchant where transaction.mcc != nil {
            add(byMCC.suggest(for: transaction)?.categoryID)
        }
        // 3. Частые категории пользователя.
        frequent.forEach(add)
        return result
    }

    /// То же, что `suggestions(for:index:categories:limit:)`, с индексом по `transactions`.
    public static func suggestions(
        for group: UncategorizedReview.Group,
        transactions: [FinanceTransaction],
        categories: [FinanceCategory],
        limit: Int = 5
    ) -> [FinanceCategory.ID] {
        suggestions(for: group, index: SuggestionIndex(transactions), categories: categories, limit: limit)
    }

    // MARK: - Прогресс

    /// Доля расходов с категорией в основной валюте (той, в которой больше всего расходов).
    public struct Progress: Equatable, Sendable {
        /// От 0 до 1.
        public let categorizedShare: Double
        public let currency: Currency
    }

    /// Прогресс разбора по сумме списаний: переводы и поступления (в том числе возвраты) не считаются.
    /// `nil`, если расходов нет.
    public static func progress(_ transactions: [FinanceTransaction]) -> Progress? {
        let expenses = transactions.filter {
            $0.deletedAt == nil && $0.kind != .transfer && $0.amount.isNegative
        }
        guard let currency = Dictionary(grouping: expenses, by: \.amount.currency)
            .max(by: { $0.value.count < $1.value.count })?.key else { return nil }
        let inCurrency = expenses.filter { $0.amount.currency == currency }
        let total = inCurrency.reduce(Int64(0)) { $0 + abs($1.amount.minorUnits) }
        guard total > 0 else { return nil }
        let categorized = inCurrency.filter { $0.categoryID != nil }.reduce(Int64(0)) { $0 + abs($1.amount.minorUnits) }
        return Progress(categorizedShare: Double(categorized) / Double(total), currency: currency)
    }

    private static func totals(of transactions: [FinanceTransaction]) -> [Money] {
        Dictionary(grouping: transactions, by: \.amount.currency)
            .map { currency, items in
                Money(minorUnits: items.reduce(0) { $0 + $1.amount.minorUnits }, currency: currency)
            }
            .sorted { abs($0.minorUnits) > abs($1.minorUnits) }
    }

    private static func magnitude(_ group: UncategorizedReview.Group) -> Int64 {
        group.totals.first.map { abs($0.minorUnits) } ?? 0
    }
}
