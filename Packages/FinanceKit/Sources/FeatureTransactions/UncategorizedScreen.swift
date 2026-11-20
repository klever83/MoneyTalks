import Categorization
import DesignSystem
import Domain
import Foundation
import SwiftUI

/// Операции без категории, сгруппированные по мерчанту. Живёт в `TransactionsViewModel`,
/// чтобы список операций показывал, сколько их осталось.
@MainActor
@Observable
final class UncategorizedViewModel {
    private(set) var groups: [UncategorizedReview.Group] = []
    /// Расходы без категории через приложение банка (MOBILE BANK): для отдельного вопроса в анкете.
    private(set) var channels: [QuickReview.ChannelGroup] = []
    private(set) var progress: QuickReview.Progress?
    /// Операции уже прочитаны из базы: до этого очередь анкеты пустая не потому, что всё разложено.
    private(set) var isLoaded = false
    /// Подсказки по тому же мерчанту из других банков: собираются один раз на изменение операций,
    /// а не на каждой карточке анкеты.
    @ObservationIgnored private var suggestionIndex = QuickReview.SuggestionIndex([])
    var errorMessage: String?

    private let transactionRepository: any TransactionRepository
    private let ruleRepository: any CategoryRuleRepository
    private let defaults: UserDefaults
    private static let snoozeKey = "quickReview.snoozedUntil"

    init(transactions: any TransactionRepository, rules: any CategoryRuleRepository, defaults: UserDefaults = .standard) {
        transactionRepository = transactions
        ruleRepository = rules
        self.defaults = defaults
    }

    /// Мерчанты, отложенные кнопкой «Не знаю»: ключ → до какого момента не спрашивать.
    var snoozedUntil: [String: Date] {
        (defaults.dictionary(forKey: Self.snoozeKey) as? [String: Double] ?? [:])
            .mapValues(Date.init(timeIntervalSince1970:))
    }

    /// Очередь анкеты на сейчас: экран анкеты берёт её снимок при открытии.
    func quickQueue(now: Date = .now) -> [UncategorizedReview.Group] {
        QuickReview.queue(groups, snoozedUntil: snoozedUntil, now: now)
    }

    func suggestions(for group: UncategorizedReview.Group, categories: [FinanceCategory]) -> [FinanceCategory.ID] {
        QuickReview.suggestions(for: group, index: suggestionIndex, categories: categories)
    }

    /// «Не знаю»: мерчант не попадёт в анкету 30 дней. Просроченные отметки заодно чистятся.
    func snooze(_ group: UncategorizedReview.Group, now: Date = .now) {
        guard case .merchant(let key) = group.id else { return }
        var stored = (defaults.dictionary(forKey: Self.snoozeKey) as? [String: Double] ?? [:])
            .filter { $0.value > now.timeIntervalSince1970 }
        stored[key] = now.addingTimeInterval(QuickReview.snoozeInterval).timeIntervalSince1970
        defaults.set(stored, forKey: Self.snoozeKey)
    }

    func markAsTransfers(_ channel: QuickReview.ChannelGroup) async {
        await save(QuickReview.markAsTransfers(channel))
    }

    /// Сколько и на какую сумму уйдёт из расходов, если ответить «Переводы на свои карты».
    func transfersSummary(_ channel: QuickReview.ChannelGroup) -> String {
        let sum = channel.totals.map { $0.negated.formatted() }.joined(separator: " + ")
        return String(localized: "Операций: \(channel.transactions.count), на сумму \(sum). Они не попадут в расходы. Отметку можно снять в карточке операции: «Это не перевод».")
    }

    func assign(_ channel: QuickReview.ChannelGroup, to categoryID: FinanceCategory.ID) async {
        await save(QuickReview.assign(channel, to: categoryID))
    }

    private func save(_ transactions: [FinanceTransaction]) async {
        do {
            try await transactionRepository.save(transactions)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var count: Int { groups.reduce(0) { $0 + $1.transactions.count } }
    var merchants: [UncategorizedReview.Group] { groups.filter(\.canCreateRule) }
    var singles: [UncategorizedReview.Group] { groups.filter { !$0.canCreateRule } }

    func observe() async {
        do {
            // Все операции, а не только без категории: по ним видно, есть ли у мерчанта покупки.
            for try await items in transactionRepository.observeTransactions(TransactionQuery()) {
                suggestionIndex = QuickReview.SuggestionIndex(items)
                groups = UncategorizedReview.groups(items)
                channels = QuickReview.channelGroups(items)
                progress = QuickReview.progress(items)
                isLoaded = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func assign(_ group: UncategorizedReview.Group, to categoryID: FinanceCategory.ID, always: Bool) async {
        do {
            let assignment = UncategorizedReview.assign(
                group, to: categoryID, always: always,
                rules: try await ruleRepository.rules()
            )
            if let rule = assignment.rule {
                try await ruleRepository.save(rule)
            }
            try await transactionRepository.save(assignment.updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Экран «Без категории»: мерчант за мерчантом, категория в одно касание.
struct UncategorizedScreen: View {
    let model: TransactionsViewModel
    @State private var selected: UncategorizedReview.Group?
    @State private var isQuickReviewPresented = false

    private var review: UncategorizedViewModel { model.review }

    var body: some View {
        List {
            if !review.merchants.isEmpty {
                Section {
                    ForEach(review.merchants) { group in
                        Button { selected = group } label: { UncategorizedGroupRow(group: group) }
                    }
                } header: {
                    Text("По мерчантам")
                } footer: {
                    Text("Категория применится ко всем операциям мерчанта.")
                }
            }
            if !review.singles.isEmpty {
                Section {
                    ForEach(review.singles) { group in
                        Button { selected = group } label: { UncategorizedGroupRow(group: group) }
                    }
                } header: {
                    Text("Без названия мерчанта")
                } footer: {
                    Text("Платежи из приложения банка, ЕРИП и переводы: по выписке не видно, за что они, поэтому они разбираются по одной.")
                }
            }
        }
        .buttonStyle(.plain)
        .overlay {
            if review.groups.isEmpty {
                ContentUnavailableView(
                    "Всё разложено",
                    systemImage: "checkmark.circle",
                    description: Text("Операций без категории нет")
                )
            }
        }
        .navigationTitle("Без категории")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("По одному") { isQuickReviewPresented = true }
                    .disabled(review.merchants.isEmpty && review.channels.isEmpty)
            }
        }
        .sheet(isPresented: $isQuickReviewPresented) {
            QuickReviewView(model: model)
        }
        .sheet(item: $selected) { group in
            AssignCategorySheet(group: group, categories: model.pickerCategories(isExpense: group.isExpense)) { categoryID, always in
                Task { await review.assign(group, to: categoryID, always: always) }
            }
        }
        .errorAlert(Binding(get: { review.errorMessage }, set: { review.errorMessage = $0 }))
    }
}

private struct UncategorizedGroupRow: View {
    let group: UncategorizedReview.Group

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(group.title)
                    .lineLimit(2)
                Group {
                    if group.transactions.count == 1, let transaction = group.transactions.first {
                        Text(transaction.bookedAt, format: .dateTime.day().month().year())
                    } else {
                        Text("Операций: \(group.transactions.count)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                ForEach(group.totals, id: \.currency) { total in
                    MoneyText(total)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

/// Выбор категории для группы. Касание категории сразу применяет её и закрывает лист.
private struct AssignCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    let group: UncategorizedReview.Group
    let categories: [(category: FinanceCategory, depth: Int)]
    let onAssign: (FinanceCategory.ID, Bool) -> Void
    @State private var always = true

    private let preview = 3

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(group.transactions.prefix(preview)) { transaction in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(transaction.merchantRaw)
                                    .font(.subheadline)
                                    .lineLimit(3)
                                Text(transaction.bookedAt, format: .dateTime.day().month().year())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            MoneyText(transaction.amount)
                        }
                    }
                    if group.transactions.count > preview {
                        Text("Ещё операций: \(group.transactions.count - preview)")
                            .foregroundStyle(.secondary)
                    }
                }
                if group.canCreateRule {
                    Section {
                        Toggle("Всегда так для «\(group.title)»", isOn: $always)
                    } footer: {
                        if always {
                            Text("Следующие операции этого мерчанта получат категорию сами.")
                        } else {
                            Text("Категория достанется только этим операциям.")
                        }
                    }
                }
                Section("Категория") {
                    ForEach(categories, id: \.category.id) { item in
                        Button {
                            onAssign(item.category.id, always && group.canCreateRule)
                            dismiss()
                        } label: {
                            CategoryPickerLabel(category: item.category, depth: item.depth)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle(group.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }
}
