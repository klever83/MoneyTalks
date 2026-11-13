import DesignSystem
@testable import FeatureSettings
import Foundation
import SwiftUI
import Testing

/// Подставной Face ID: отвечает заранее заданным результатом и считает запросы.
final class FakeAuthenticator: DeviceAuthenticator, @unchecked Sendable {
    private let lock = NSLock()
    private var _results: [Bool]
    private var _requests = 0
    let available: DeviceAuthMethod

    init(results: [Bool], method: DeviceAuthMethod = .faceID) {
        _results = results
        available = method
    }

    var requests: Int { lock.withLock { _requests } }

    func method() -> DeviceAuthMethod { available }

    func authenticate(reason: String) async -> Bool {
        lock.withLock {
            _requests += 1
            return _results.isEmpty ? false : _results.removeFirst()
        }
    }
}

@MainActor
@Suite("Блокировка приложения")
struct AppLockTests {
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: "AppLockTests-\(UUID().uuidString)")!
    }

    @Test("Включение требует подтверждения, отказ ничего не меняет")
    func enabling() async {
        let authenticator = FakeAuthenticator(results: [false, true])
        let lock = AppLock(authenticator: authenticator, defaults: defaults)
        #expect(!lock.isEnabled && !lock.isLocked)

        #expect(await lock.setEnabled(true) == false)
        #expect(!lock.isEnabled && !defaults.bool(forKey: SettingsKey.appLockEnabled))

        #expect(await lock.setEnabled(true))
        #expect(lock.isEnabled && defaults.bool(forKey: SettingsKey.appLockEnabled))
        // Включение не запирает уже открытое приложение.
        #expect(!lock.isLocked)
        #expect(authenticator.requests == 2)
    }

    @Test("Без код-пароля на устройстве блокировку не включить")
    func unavailable() async {
        let authenticator = FakeAuthenticator(results: [true], method: .unavailable)
        let lock = AppLock(authenticator: authenticator, defaults: defaults)
        #expect(await lock.setEnabled(true) == false)
        #expect(authenticator.requests == 0)
    }

    @Test("Запуск с включённой блокировкой: заперто, содержимое закрыто до разблокировки")
    func launchLocked() async {
        defaults.set(true, forKey: SettingsKey.appLockEnabled)
        let lock = AppLock(authenticator: FakeAuthenticator(results: [false, true]), defaults: defaults)
        #expect(lock.isLocked && lock.shouldCover(.active))

        await lock.unlock()
        #expect(lock.isLocked)
        await lock.unlock()
        #expect(!lock.isLocked && !lock.shouldCover(.active))
    }

    @Test("Запирается только уход в фон; Face ID сам — только при возвращении из фона")
    func scenePhases() async {
        defaults.set(true, forKey: SettingsKey.appLockEnabled)
        let lock = AppLock(authenticator: FakeAuthenticator(results: [true, false]), defaults: defaults)
        await lock.unlock()
        #expect(!lock.isLocked)

        // Пункт управления или окно системы: сцена неактивна, но не заперта, суммы скрыты.
        #expect(lock.sceneDidChange(to: .inactive) == false)
        #expect(!lock.isLocked && lock.shouldCover(.inactive))
        #expect(lock.sceneDidChange(to: .active) == false)

        // Свернули и вернулись: заперто, разблокировка запрашивается сразу.
        _ = lock.sceneDidChange(to: .inactive)
        _ = lock.sceneDidChange(to: .background)
        #expect(lock.isLocked)
        _ = lock.sceneDidChange(to: .inactive)
        #expect(lock.sceneDidChange(to: .active))

        // Пользователь отменил Face ID: окно закрылось, сцена снова активна, но повторного запроса нет.
        await lock.unlock()
        #expect(lock.isLocked)
        _ = lock.sceneDidChange(to: .inactive)
        #expect(lock.sceneDidChange(to: .active) == false)
    }

    @Test("Выключенная блокировка ничего не запирает и не закрывает")
    func disabled() {
        let lock = AppLock(authenticator: FakeAuthenticator(results: []), defaults: defaults)
        _ = lock.sceneDidChange(to: .background)
        #expect(!lock.isLocked && !lock.shouldCover(.inactive))
        #expect(lock.sceneDidChange(to: .active) == false)
    }

    @Test("Выключение тоже требует подтверждения")
    func disabling() async {
        defaults.set(true, forKey: SettingsKey.appLockEnabled)
        let lock = AppLock(authenticator: FakeAuthenticator(results: [true, false, true]), defaults: defaults)
        await lock.unlock()
        #expect(await lock.setEnabled(false) == false)
        #expect(lock.isEnabled)
        #expect(await lock.setEnabled(false))
        #expect(!lock.isEnabled && !defaults.bool(forKey: SettingsKey.appLockEnabled))
    }

    @Test("Код-пароль убран при включённой блокировке: приложение не запирается навсегда")
    func passcodeRemoved() async {
        defaults.set(true, forKey: SettingsKey.appLockEnabled)
        let authenticator = FakeAuthenticator(results: [], method: .unavailable)
        let lock = AppLock(authenticator: authenticator, defaults: defaults)
        #expect(lock.isLocked)
        await lock.unlock()
        #expect(!lock.isLocked && authenticator.requests == 0)
    }

    @Test("Холодный запуск в неактивной сцене: Face ID запрашивается на первом переходе в активную")
    func coldLaunchInactive() async {
        defaults.set(true, forKey: SettingsKey.appLockEnabled)
        let lock = AppLock(authenticator: FakeAuthenticator(results: [false]), defaults: defaults)
        #expect(lock.sceneDidChange(to: .active))
        // Отменили: повторного автоматического запроса нет.
        await lock.unlock()
        _ = lock.sceneDidChange(to: .inactive)
        #expect(lock.sceneDidChange(to: .active) == false)
    }
}
