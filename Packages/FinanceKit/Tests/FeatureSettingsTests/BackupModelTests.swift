import DesignSystem
import Domain
@testable import FeatureSettings
import Foundation
import Testing

@MainActor
@Suite("Резервная копия: модель экрана")
struct BackupModelTests {
    struct FakeBackup: BackupService {
        let fails: Bool
        func exportBackup(to url: URL) async throws {}
        func restoreBackup(from url: URL) async throws {
            if fails { throw BackupError.notBackup }
        }
    }

    @Test("После восстановления сохранённые операции раскладываются заново: версия правил сбрасывается")
    func restoreResetsRulesVersion() async throws {
        let defaults = try #require(UserDefaults(suiteName: "BackupModelTests-\(UUID())"))
        defaults.set(2, forKey: SettingsKey.categorizedWithRulesVersion)

        let failing = BackupModel(service: FakeBackup(fails: true), defaults: defaults)
        failing.pendingRestore = URL(fileURLWithPath: "/tmp/copy.sqlite")
        await failing.restore()
        #expect(defaults.integer(forKey: SettingsKey.categorizedWithRulesVersion) == 2)

        let model = BackupModel(service: FakeBackup(fails: false), defaults: defaults)
        model.pendingRestore = URL(fileURLWithPath: "/tmp/copy.sqlite")
        await model.restore()
        #expect(defaults.object(forKey: SettingsKey.categorizedWithRulesVersion) == nil)
    }
}
