import DesignSystem
import Domain
import SwiftUI

/// Палитра и иконки для категорий: выбор из готовых, без ввода hex-кодов.
enum CategoryAppearance {
    static let colors = [
        "#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#30B0C7", "#007AFF",
        "#5856D6", "#AF52DE", "#FF2D55", "#A2845E", "#8E8E93", "#64D2FF",
    ]

    static let symbols = [
        "tag", "cart", "fork.knife", "cup.and.saucer", "bus", "car", "fuelpump", "house",
        "bolt", "drop", "antenna.radiowaves.left.and.right", "cross.case", "pills", "tshirt",
        "bag", "gift", "gamecontroller", "film", "music.note", "book", "graduationcap", "airplane",
        "pawprint", "figure.child", "dumbbell", "scissors", "wrench.and.screwdriver", "creditcard",
        "banknote", "repeat", "heart", "star",
    ]
}

/// Создание и правка категории: название, родитель, иконка и цвет.
struct CategoryEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State private var category: FinanceCategory
    private let isNew: Bool
    private let parents: [FinanceCategory]
    private let onSave: (FinanceCategory) async -> Bool
    private let onDeleteRule: (CategoryRule) async -> Void
    @State private var rules: [CategoryRule]
    /// Смахнутые правила удаляются только по «Сохранить»: «Отмена» их возвращает.
    @State private var removedRules: [CategoryRule] = []
    @State private var isSaving = false

    init(
        category: FinanceCategory,
        isNew: Bool,
        parents: [FinanceCategory],
        rules: [CategoryRule] = [],
        onDeleteRule: @escaping (CategoryRule) async -> Void = { _ in },
        onSave: @escaping (FinanceCategory) async -> Bool
    ) {
        _category = State(initialValue: category)
        _rules = State(initialValue: rules)
        self.isNew = isNew
        self.parents = parents
        self.onDeleteRule = onDeleteRule
        self.onSave = onSave
    }

    private var canSave: Bool {
        !category.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if category.isSystem {
                        LabeledContent("Название", value: category.displayName)
                    } else {
                        TextField("Название", text: $category.name)
                    }
                    if !parents.isEmpty || category.parentID != nil {
                        Picker("Входит в", selection: $category.parentID) {
                            Text("Верхний уровень").tag(FinanceCategory.ID?.none)
                            ForEach(parents) { parent in
                                Text(parent.displayName).tag(Optional(parent.id))
                            }
                        }
                    }
                    if category.isSystem {
                        Toggle("Скрыть", isOn: $category.isHidden)
                    }
                } footer: {
                    if category.isHidden {
                        Text("Скрытая категория не предлагается при выборе и в автокатегоризации, но остаётся у старых операций.")
                    }
                }

                if !rules.isEmpty {
                    Section {
                        ForEach(rules) { rule in
                            Text(rule.summary)
                        }
                        .onDelete { offsets in
                            removedRules += offsets.map { rules[$0] }
                            rules.remove(atOffsets: offsets)
                        }
                    } header: {
                        Text("Всегда так")
                    } footer: {
                        Text("Операции этих мерчантов получают категорию автоматически. Смахните, чтобы удалить правило: удаление применится при сохранении.")
                    }
                }

                Section("Цвет") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(CategoryAppearance.colors, id: \.self) { hex in
                            Button {
                                category.colorHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex) ?? .gray)
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if category.colorHex == hex {
                                            Image(systemName: "checkmark").foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(hex)
                            .accessibilityAddTraits(category.colorHex == hex ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Иконка") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(symbols, id: \.self) { symbol in
                            Button {
                                category.systemImage = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.title3)
                                    .frame(width: 36, height: 36)
                                    .foregroundStyle(category.systemImage == symbol ? .white : category.color)
                                    .background(
                                        category.systemImage == symbol ? category.color : Color.clear,
                                        in: .rect(cornerRadius: 8)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(symbol)
                            .accessibilityAddTraits(category.systemImage == symbol ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(isNew ? "Новая категория" : "Категория")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        isSaving = true
                        Task {
                            let saved = await onSave(category)
                            if saved {
                                for rule in removedRules { await onDeleteRule(rule) }
                            }
                            isSaving = false
                            if saved { dismiss() }
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    /// Иконка системной категории может быть не из набора: тогда она идёт первой.
    private var symbols: [String] {
        CategoryAppearance.symbols.contains(category.systemImage)
            ? CategoryAppearance.symbols
            : [category.systemImage] + CategoryAppearance.symbols
    }
}

extension CategoryRule {
    /// Правило одной строкой: `Evroopt`, `MCC 5411–5499`, `«кофе», расход`.
    var summary: String {
        conditions.map { condition in
            switch condition {
            case .merchantKey(let key):
                key.capitalized(with: Locale(identifier: "ru_BY"))
            case .merchantContains(let text), .merchantEquals(let text), .merchantWord(let text):
                "«\(text)»"
            case .mccRange(let range):
                range.lowerBound == range.upperBound ? "MCC \(range.lowerBound)" : "MCC \(range.lowerBound)–\(range.upperBound)"
            case .amountSign(.negative):
                String(localized: "расход")
            case .amountSign(.positive):
                String(localized: "доход")
            case .account:
                String(localized: "счёт")
            }
        }
        .joined(separator: ", ")
    }
}
