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
    @State private var lock = AppLock()
    @State private var selectedTab = RootTab.overview
    /// Выписка, открытая в MoneyTalks через «Поделиться» или «Открыть в»: её подхватывает вкладка импорта.
    @State private var incomingFile: URL?
    /// Анкета разбора трат, открытая с экрана импорта.
    @State private var isQuickReviewPresented = false

    private enum RootTab: Hashable {
        case overview, transactions, `import`, accounts, settings
    }

    public init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Обзор", systemImage: "chart.pie", value: .overview) {
                AnalyticsScreen(
                    analytics: dependencies.analytics,
                    categories: dependencies.categories,
                    loadRates: { [loader = dependencies.exchangeRates] keys in _ = await loader.load(keys) }
                )
            }
            Tab("Операции", systemImage: "list.bullet.rectangle", value: .transactions) {
                TransactionsScreen(
                    transactions: dependencies.transactions,
                    accounts: dependencies.accounts,
                    categories: dependencies.categories,
                    categorizer: dependencies.categorizer,
                    rules: dependencies.categoryRules,
                    isQuickReviewPresented: $isQuickReviewPresented
                )
            }
            Tab("Импорт", systemImage: "square.and.arrow.down", value: .import) {
                ImportScreen(
                    registry: dependencies.parserRegistry,
                    banks: BankParsersBY.banks,
                    accounts: dependencies.accounts,
                    transactions: dependencies.transactions,
                    imports: dependencies.imports,
                    categorizer: dependencies.categorizer,
                    incomingFile: $incomingFile,
                    onReviewCategories: {
                        selectedTab = .transactions
                        isQuickReviewPresented = true
                    }
                )
            }
            Tab("Счета", systemImage: "creditcard", value: .accounts) {
                AccountsScreen(repository: dependencies.accounts)
            }
            Tab("Настройки", systemImage: "gearshape", value: .settings) {
                SettingsScreen(lock: lock, backup: dependencies.backup) {
                    CategoriesScreen(repository: dependencies.categories, rules: dependencies.categoryRules)
                }
            }
        }
        .onOpenURL { url in
            guard url.isFileURL else { return }
            incomingFile = url
            selectedTab = .import
        }
        .appLock(lock)
        .preferredColorScheme(appearance.colorScheme)
    }
}

#Preview {
    if let dependencies = try? Dependencies.inMemory() {
        AppRootView(dependencies: dependencies)
    }
}
