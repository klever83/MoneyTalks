import DesignSystem
import StatementImport
import SwiftUI

/// Вкладка импорта выписок. Пока заглушка: парсеры появятся после получения образцов выписок.
public struct ImportScreen: View {
    private let registry: ParserRegistry
    private let banks: [BankInfo]

    public init(registry: ParserRegistry, banks: [BankInfo]) {
        self.registry = registry
        self.banks = banks
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(banks, id: \.id) { bank in
                        HStack {
                            Text(bank.name)
                            Spacer()
                            Text("Скоро")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Поддерживаемые банки")
                } footer: {
                    Text("Выгрузите выписку в приложении банка и поделитесь файлом с MoneyTalks.")
                }
            }
            .navigationTitle("Импорт")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Выбрать файл", systemImage: "doc.badge.plus") {}
                        .disabled(registry.parsers.isEmpty)
                }
            }
        }
    }
}
