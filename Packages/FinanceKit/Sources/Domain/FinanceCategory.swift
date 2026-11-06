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
        self.sortOrder = sortOrder
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    public var isSystem: Bool { systemKey != nil }
}
