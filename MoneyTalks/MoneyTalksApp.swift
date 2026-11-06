import AppComposition
import SwiftUI

@main
struct MoneyTalksApp: App {
    private let dependencies: Dependencies

    init() {
        do {
            dependencies = try .live()
        } catch {
            fatalError("Не удалось открыть базу данных: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(dependencies: dependencies)
        }
    }
}
