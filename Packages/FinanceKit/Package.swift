// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FinanceKit",
    defaultLocalization: "ru",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "AppComposition", targets: ["AppComposition"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        // Ядро: модели и протоколы, ни от чего не зависит.
        .target(name: "Domain"),

        // Сервисы и данные.
        .target(name: "Persistence", dependencies: ["Domain", .product(name: "GRDB", package: "GRDB.swift")]),
        .target(name: "StatementImport", dependencies: ["Domain"]),
        .target(name: "BankParsersBY", dependencies: ["Domain", "StatementImport"]),
        .target(name: "Categorization", dependencies: ["Domain"]),
        .target(name: "ExchangeRates", dependencies: ["Domain"]),
        .target(name: "Analytics", dependencies: ["Domain"]),
        .target(name: "DesignSystem", dependencies: ["Domain"]),

        // Фичи: экраны + view model.
        .target(name: "FeatureTransactions", dependencies: ["Domain", "DesignSystem", "Categorization"]),
        .target(name: "FeatureImport", dependencies: ["Domain", "DesignSystem", "StatementImport"]),
        .target(name: "FeatureAnalytics", dependencies: ["Domain", "DesignSystem", "Analytics"]),
        .target(name: "FeatureAccounts", dependencies: ["Domain", "DesignSystem"]),
        .target(name: "FeatureCategories", dependencies: ["Domain", "DesignSystem"]),
        .target(name: "FeatureSettings", dependencies: ["Domain", "DesignSystem"]),

        // Сборка зависимостей и корневая навигация.
        .target(
            name: "AppComposition",
            dependencies: [
                "Domain", "Persistence", "StatementImport", "BankParsersBY", "Categorization",
                "ExchangeRates", "Analytics", "DesignSystem",
                "FeatureTransactions", "FeatureImport", "FeatureAnalytics",
                "FeatureAccounts", "FeatureCategories", "FeatureSettings",
            ]
        ),

        .testTarget(name: "DomainTests", dependencies: ["Domain"]),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence", "Categorization"]),
        .testTarget(name: "StatementImportTests", dependencies: ["StatementImport", "Domain", "Analytics"]),
        .testTarget(name: "BankParsersBYTests", dependencies: ["BankParsersBY", "StatementImport", "Domain"]),
        .testTarget(name: "CategorizationTests", dependencies: ["Categorization"]),
        .testTarget(name: "ExchangeRatesTests", dependencies: ["ExchangeRates"]),
        .testTarget(name: "AnalyticsTests", dependencies: ["Analytics"]),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
        .testTarget(name: "FeatureAccountsTests", dependencies: ["FeatureAccounts", "Domain"]),
        .testTarget(name: "FeatureTransactionsTests", dependencies: ["FeatureTransactions", "Persistence", "Categorization"]),
    ]
)
