import DesignSystem
import Domain
import SwiftUI

public struct SettingsScreen<Categories: View>: View {
    @AppStorage(SettingsKey.baseCurrencyCode) private var baseCurrencyCode = Currency.byn.code
    @AppStorage(SettingsKey.convertToBaseCurrency) private var convertToBaseCurrency = true
    @AppStorage(SettingsKey.appearance) private var appearance: Appearance = .dark

    private let categories: () -> Categories

    public init(@ViewBuilder categories: @escaping () -> Categories) {
        self.categories = categories
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Основная валюта", selection: $baseCurrencyCode) {
                        ForEach(Currency.supported) { currency in
                            Text(currency.code).tag(currency.code)
                        }
                    }
                    Toggle("Пересчитывать в основную валюту", isOn: $convertToBaseCurrency)
                } header: {
                    Text("Валюта")
                } footer: {
                    Text(convertToBaseCurrency
                        ? "Итоги и графики пересчитываются по курсу НБ РБ на дату операции."
                        : "Итоги показываются отдельно по каждой валюте.")
                }

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
