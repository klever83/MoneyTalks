import DesignSystem
import SwiftUI

public struct SettingsScreen<Categories: View>: View {
    @AppStorage(SettingsKey.appearance) private var appearance: Appearance = .dark

    private let categories: () -> Categories

    public init(@ViewBuilder categories: @escaping () -> Categories) {
        self.categories = categories
    }

    public var body: some View {
        NavigationStack {
            Form {
                // Основная валюта и пересчёт по курсу НБ РБ вернутся вместе с кэшем курсов (#10):
                // пока аналитика считает итоги отдельно по каждой валюте, переключатель ничего бы не менял.

                Section("Оформление") {
                    Picker("Тема", selection: $appearance) {
                        ForEach(Appearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                }

                Section {
                    NavigationLink("Категории") { categories() }
                }
            }
            .navigationTitle("Настройки")
        }
    }
}
