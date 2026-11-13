import DesignSystem
import Domain
import SwiftUI

public struct SettingsScreen<Categories: View>: View {
    @AppStorage(SettingsKey.appearance) private var appearance: Appearance = .dark
    @AppStorage(SettingsKey.convertToBaseCurrency) private var convertsToBase = true
    @AppStorage(SettingsKey.baseCurrencyCode) private var baseCurrencyCode = Currency.byn.code

    private let lock: AppLock
    private let categories: () -> Categories

    public init(lock: AppLock, @ViewBuilder categories: @escaping () -> Categories) {
        self.lock = lock
        self.categories = categories
    }

    /// Чем подтверждается владелец: Face ID, Touch ID или код-пароль.
    private var method: DeviceAuthMethod { lock.method }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Пересчитывать в основную валюту", isOn: $convertsToBase)
                    if convertsToBase {
                        Picker("Основная валюта", selection: $baseCurrencyCode) {
                            ForEach(Currency.supported) { currency in
                                Text(currency.code).tag(currency.code)
                            }
                        }
                    }
                } header: {
                    Text("Валюта")
                } footer: {
                    Text(convertsToBase
                        ? "Итоги в Обзоре пересчитываются по официальному курсу НБ РБ на день операции."
                        : "Итоги в Обзоре показываются отдельно по каждой валюте.")
                }

                Section("Оформление") {
                    Picker("Тема", selection: $appearance) {
                        ForEach(Appearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { lock.isEnabled },
                        set: { enabled in Task { await lock.setEnabled(enabled) } }
                    )) {
                        Text("Блокировка: \(Text(method.title))")
                    }
                    .disabled(method == .unavailable || lock.isAuthenticating)
                } header: {
                    Text("Безопасность")
                } footer: {
                    if method == .unavailable {
                        Text("Чтобы включить блокировку, задайте код-пароль в настройках устройства.")
                    } else {
                        Text("При возвращении в приложение после сворачивания понадобится \(Text(method.title)). В переключателе приложений суммы скрыты.")
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
