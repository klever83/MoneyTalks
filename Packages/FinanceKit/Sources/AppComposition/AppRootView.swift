import BankParsersBY
import DesignSystem
import FeatureAccounts
import FeatureAnalytics
import FeatureCategories
import FeatureImport
import FeatureSettings
import FeatureTransactions
import SwiftUI

public struct AppRootView: View {
    private let dependencies: Dependencies
    @AppStorage(SettingsKey.appearance) private var appearance: Appearance = .dark

    public init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    public var body: some View {
        TabView {
            Tab("Операции", systemImage: "list.bullet.rectangle") {
                TransactionsScreen(
                    transactions: dependencies.transactions,
                    accounts: dependencies.accounts,
                    categories: dependencies.categories,
                    categorizer: dependencies.categorizer
                )
            }
            Tab("Аналитика", systemImage: "chart.pie") {
                AnalyticsScreen(transactions: dependencies.transactions)
            }
            Tab("Импорт", systemImage: "square.and.arrow.down") {
                ImportScreen(
                    registry: dependencies.parserRegistry,
                    banks: BankParsersBY.banks,
                    accounts: dependencies.accounts,
                    transactions: dependencies.transactions,
                    imports: dependencies.imports,
                    categorizer: dependencies.categorizer
                )
            }
            Tab("Счета", systemImage: "creditcard") {
                AccountsScreen(repository: dependencies.accounts)
            }
            Tab("Настройки", systemImage: "gearshape") {
                SettingsScreen {
                    CategoriesScreen(repository: dependencies.categories)
                }
            }
        }
        .preferredColorScheme(appearance.colorScheme)
    }
}

#Preview {
    if let dependencies = try? Dependencies.inMemory() {
        AppRootView(dependencies: dependencies)
    }
}
