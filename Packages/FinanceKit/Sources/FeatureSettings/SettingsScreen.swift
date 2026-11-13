import DesignSystem
import SwiftUI

public struct SettingsScreen<Categories: View>: View {
    @AppStorage(SettingsKey.appearance) private var appearance: Appearance = .dark

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
