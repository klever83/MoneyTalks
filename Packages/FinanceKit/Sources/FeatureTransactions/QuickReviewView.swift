import Categorization
import DesignSystem
import Domain
import SwiftUI

/// Анкета «что это за место?»: по карточке на мерчанта, ответ в одно касание.
///
/// Очередь фиксируется при открытии, чтобы карточки не прыгали, пока ответы сохраняются.
/// Каждый ответ по мерчанту сохраняется сразу как правило «всегда так»: анкету можно закрыть
/// в любой момент, сделанное не теряется.
struct QuickReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let model: TransactionsViewModel
    @AppStorage("quickReview.introSeen") private var introSeen = false
    @State private var steps: [Step]?
    @State private var index = 0
    @State private var startShare: Double?
    @State private var chips: [FinanceCategory] = []
    @State private var pickingCategoryFor: Step?

    private var review: UncategorizedViewModel { model.review }

    enum Step: Identifiable {
        case channel(QuickReview.ChannelGroup)
        case merchant(UncategorizedReview.Group)

        var id: String {
            switch self {
            case .channel(let channel):
                return "channel-\(channel.id)"
            case .merchant(let group):
                guard case .merchant(let key) = group.id else { return "merchant" }
                return "merchant-\(key)"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !introSeen {
                    intro
                } else if steps == nil {
                    ProgressView()
                } else if let steps, index < steps.count {
                    VStack(alignment: .leading, spacing: 16) {
                        ProgressView(value: Double(index), total: Double(steps.count))
                        Text("\(index + 1) из \(steps.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ScrollView {
                            card(for: steps[index])
                        }
                    }
                    .padding()
                } else {
                    done
                }
            }
            .navigationTitle("Разбор трат")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .onAppear(perform: start)
        .onChange(of: review.isLoaded) { start() }
        .onChange(of: index) { updateChips() }
        .sheet(item: $pickingCategoryFor) { step in
            CategoryListSheet(categories: model.pickerCategories(isExpense: true)) { categoryID in
                answer(step, with: categoryID)
            }
        }
        .errorAlert(Binding(get: { review.errorMessage }, set: { review.errorMessage = $0 }))
    }

    // MARK: - Экраны

    private var intro: some View {
        ContentUnavailableView {
            Label("Разложим траты по категориям", systemImage: "square.grid.2x2")
        } description: {
            Text("Банк не пишет, что это за места. Ответь один раз про каждое, дальше MoneyTalks будет раскладывать их сам. Всё остаётся на телефоне.")
        } actions: {
            Button("Начать") { introSeen = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private var done: some View {
        ContentUnavailableView {
            Label(
                steps?.isEmpty == true ? String(localized: "Всё разложено") : String(localized: "Готово"),
                systemImage: "checkmark.circle"
            )
        } description: {
            if let share = review.progress?.categorizedShare {
                if let startShare, startShare < share {
                    Text("Разобрано \(percent(share)) трат, было \(percent(startShare)).")
                } else {
                    Text("Разобрано \(percent(share)) трат.")
                }
            }
        } actions: {
            Button("Готово") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private func card(for step: Step) -> some View {
        switch step {
        case .merchant(let group):
            VStack(alignment: .leading, spacing: 16) {
                header(title: group.title, count: group.transactions.count, totals: group.totals)
                samples(group.transactions)
                Text("Что это за место?")
                    .font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 8) {
                    ForEach(chips) { category in
                        Button {
                            answer(step, with: category.id)
                        } label: {
                            Label(category.displayName, systemImage: category.systemImage)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                Button("Другая категория…") { pickingCategoryFor = step }
                Button("Не знаю") {
                    review.snooze(group)
                    next()
                }
                .foregroundStyle(.secondary)
                Text("Ответ запомнится для следующих выписок.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .channel(let channel):
            VStack(alignment: .leading, spacing: 16) {
                header(title: channel.title, count: channel.transactions.count, totals: channel.totals)
                Text("Это платежи из приложения банка: по выписке не видно, за что они. Что это чаще всего?")
                Button {
                    Task { await review.markAsTransfers(channel) }
                    next()
                } label: {
                    VStack(alignment: .leading) {
                        Text("Переводы на свои карты")
                        Text("Не попадут в доходы и расходы")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                Button {
                    pickingCategoryFor = step
                } label: {
                    VStack(alignment: .leading) {
                        Text("Переводы людям или оплата")
                        Text("Выбрать одну категорию для всех")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                Button("Разные, разберу сам на экране «Без категории»") { next() }
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func header(title: String, count: Int, totals: [Money]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.bold())
            HStack {
                Text("Операций: \(count)")
                Spacer()
                ForEach(totals, id: \.currency) { total in
                    MoneyText(total)
                }
            }
            .foregroundStyle(.secondary)
        }
    }

    /// Строки из выписки: город и точка часто подсказывают, что это за место.
    private func samples(_ transactions: [FinanceTransaction]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(transactions.prefix(2)) { transaction in
                Text(transaction.merchantRaw)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Действия

    private func start() {
        guard steps == nil, review.isLoaded else { return }
        startShare = review.progress?.categorizedShare
        steps = review.channels.map(Step.channel) + review.quickQueue().map(Step.merchant)
        updateChips()
    }

    private func answer(_ step: Step, with categoryID: FinanceCategory.ID) {
        switch step {
        case .merchant(let group):
            Task { await review.assign(group, to: categoryID, always: true) }
        case .channel(let channel):
            Task { await review.assign(channel, to: categoryID) }
        }
        next()
    }

    private func next() {
        index += 1
    }

    private func updateChips() {
        guard let steps, index < steps.count, case .merchant(let group) = steps[index] else {
            chips = []
            return
        }
        let allowed = model.pickerCategories(isExpense: group.isExpense).map(\.category)
        let ids = review.suggestions(for: group, categories: allowed)
        chips = ids.compactMap { id in allowed.first { $0.id == id } }
    }

    private func percent(_ share: Double) -> String {
        share.formatted(.percent.precision(.fractionLength(0)))
    }
}

/// Полный список категорий для «Другая категория…».
private struct CategoryListSheet: View {
    @Environment(\.dismiss) private var dismiss
    let categories: [(category: FinanceCategory, depth: Int)]
    let onPick: (FinanceCategory.ID) -> Void

    var body: some View {
        NavigationStack {
            List(categories, id: \.category.id) { item in
                Button {
                    onPick(item.category.id)
                    dismiss()
                } label: {
                    CategoryPickerLabel(category: item.category, depth: item.depth)
                        .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Категория")
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
