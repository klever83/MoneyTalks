import Domain
import SwiftUI

extension Account.Kind {
    public var title: LocalizedStringKey {
        switch self {
        case .card: "Карта"
        case .current: "Текущий счёт"
        case .savings: "Вклад"
        case .cash: "Наличные"
        }
    }

    public var systemImage: String {
        switch self {
        case .card: "creditcard"
        case .current: "building.columns"
        case .savings: "banknote"
        case .cash: "wallet.bifold"
        }
    }
}

extension FinanceCategory {
    /// Название для показа: системные категории локализуются по ключу, пользовательские — как ввели.
    public var displayName: String {
        guard let systemKey else { return name }
        return Bundle.main.localizedString(forKey: "category.\(systemKey)", value: name, table: nil)
    }

    public var color: Color {
        Color(hex: colorHex) ?? .gray
    }
}

extension Color {
    /// `#RRGGBB` → `Color`.
    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
