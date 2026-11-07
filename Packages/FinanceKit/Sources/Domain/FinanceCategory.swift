import Foundation

/// Категория расходов или доходов. Два уровня: «Еда → Рестораны».
///
/// Названо `FinanceCategory`, а не `Category`, чтобы не конфликтовать с `ObjectiveC.Category`.
public struct FinanceCategory: Identifiable, Hashable, Codable, Sendable {
    public typealias ID = Identifier<FinanceCategory>

    public enum Kind: String, Codable, Sendable, CaseIterable {
        case expense, income
    }

    public var id: ID
    /// Название, введённое пользователем. Для системных категорий отображается локализация по `systemKey`.
    public var name: String
    /// Ключ системной категории (`groceries`, `transport`…), `nil` у пользовательских.
    public var systemKey: String?
    public var systemImage: String
    public var colorHex: String
    public var parentID: ID?
    public var kind: Kind
    /// Скрытая категория не предлагается при выборе и в правилах, но остаётся у старых операций.
    /// Системные категории не удаляются, а скрываются.
    public var isHidden: Bool
    public var sortOrder: Int
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: ID = ID(),
        name: String,
        systemKey: String? = nil,
        systemImage: String,
        colorHex: String,
        parentID: ID? = nil,
        kind: Kind,
        isHidden: Bool = false,
        sortOrder: Int = 0,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.systemKey = systemKey
        self.systemImage = systemImage
        self.colorHex = colorHex
        self.parentID = parentID
        self.kind = kind
        self.isHidden = isHidden
        self.sortOrder = sortOrder
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    public var isSystem: Bool { systemKey != nil }

    /// Категории в порядке показа: родитель, за ним его подкатегории. `depth` 0 или 1.
    /// Подкатегория, чей родитель не в списке (удалён или другого типа), показывается на верхнем уровне.
    public static func tree(_ categories: [FinanceCategory]) -> [(category: FinanceCategory, depth: Int)] {
        let ids = Set(categories.map(\.id))
        let roots = categories.filter { $0.parentID.map { !ids.contains($0) } ?? true }
        let children = Dictionary(grouping: categories.filter { $0.parentID.map(ids.contains) ?? false }) { $0.parentID! }
        return roots.flatMap { root in
            [(root, 0)] + (children[root.id] ?? []).map { ($0, 1) }
        }
    }
}
