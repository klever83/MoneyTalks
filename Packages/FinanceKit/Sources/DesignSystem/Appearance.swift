import SwiftUI

/// Тема оформления. По макетам основная — тёмная, но пользователь может выбрать.
public enum Appearance: String, CaseIterable, Identifiable, Sendable {
    case system, dark, light

    public var id: String { rawValue }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .dark: .dark
        case .light: .light
        }
    }

    public var title: LocalizedStringKey {
        switch self {
        case .system: "Как в системе"
        case .dark: "Тёмная"
        case .light: "Светлая"
        }
    }
}

/// Ключи пользовательских настроек.
public enum SettingsKey {
    public static let appearance = "appearance"
    public static let baseCurrencyCode = "baseCurrencyCode"
    public static let convertToBaseCurrency = "convertToBaseCurrency"
}
