import DesignSystem
import Foundation
import LocalAuthentication
import Observation
import SwiftUI

/// Чем устройство подтверждает владельца.
public enum DeviceAuthMethod: Sendable, Equatable {
    case faceID, touchID, opticID
    /// Биометрии нет или она не настроена, но есть код-пароль.
    case passcode
    /// На устройстве нет даже код-пароля: блокировку включить нельзя.
    case unavailable

    var title: LocalizedStringKey {
        switch self {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        case .passcode, .unavailable: "Код-пароль"
        }
    }
}

/// Подтверждение владельца устройства.
public protocol DeviceAuthenticator: Sendable {
    func method() -> DeviceAuthMethod
    /// `true`, если владелец подтвердил. Биометрия с откатом на код-пароль.
    /// Если с устройства убран код-пароль, подтверждать нечем: `AppLock` тогда не запирает.
    func authenticate(reason: String) async -> Bool
}

/// LocalAuthentication: Face ID, Touch ID или Optic ID, а без них код-пароль устройства.
public struct LocalDeviceAuthenticator: DeviceAuthenticator {
    public init() {}

    public func method() -> DeviceAuthMethod {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return .unavailable }
        // biometryType заполняется после canEvaluatePolicy.
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return .passcode }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .passcode
        }
    }

    public func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}

/// Блокировка приложения (#19): при уходе в фон приложение запирается, вернуться можно только
/// после Face ID (или Touch ID, или код-пароля). Включение и выключение тоже подтверждаются,
/// чтобы блокировку не снял тот, кому дали разблокированный телефон.
@MainActor
@Observable
public final class AppLock {
    public private(set) var isEnabled: Bool
    public private(set) var isLocked: Bool
    /// Идёт проверка: повторный запрос не запускается.
    public private(set) var isAuthenticating = false
    /// Приложение было в фоне: при возвращении Face ID запрашивается сам.
    private var returnsFromBackground = false

    private let authenticator: any DeviceAuthenticator
    private let defaults: UserDefaults

    public init(authenticator: any DeviceAuthenticator = LocalDeviceAuthenticator(), defaults: UserDefaults = .standard) {
        self.authenticator = authenticator
        self.defaults = defaults
        let enabled = defaults.bool(forKey: SettingsKey.appLockEnabled)
        isEnabled = enabled
        // При запуске с включённой блокировкой приложение сразу заперто, а Face ID запрашивается
        // на первом `.active`: в ещё неактивной сцене запрос может сразу завершиться ошибкой.
        isLocked = enabled
        returnsFromBackground = enabled
    }

    public var method: DeviceAuthMethod { authenticator.method() }

    /// Скрывать содержимое: в переключателе приложений и пока приложение заперто.
    public func shouldCover(_ phase: ScenePhase) -> Bool {
        isEnabled && (isLocked || phase != .active)
    }

    /// Смена состояния сцены. Запирается только уход в фон: окно Face ID и пункт управления
    /// делают сцену неактивной, и блокировка на них зациклилась бы.
    /// - Returns: пора запросить разблокировку сразу. Только при возвращении из фона: если
    ///   пользователь отменил Face ID, сцена снова станет активной, и повторный запрос по этому
    ///   событию не давал бы закрыть окно.
    public func sceneDidChange(to phase: ScenePhase) -> Bool {
        switch phase {
        case .background:
            if isEnabled { isLocked = true }
            returnsFromBackground = true
            return false
        case .active:
            defer { returnsFromBackground = false }
            return returnsFromBackground && isLocked
        default:
            return false
        }
    }

    public func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        // Запрос уже идёт: отмена окна Face ID не должна вызвать ещё один автоматический.
        returnsFromBackground = false
        // Код-пароль с устройства убран: подтвердить владельца нечем, а само устройство открыто.
        // Иначе приложение заперлось бы навсегда вместе с переключателем в Настройках.
        if authenticator.method() == .unavailable {
            isLocked = false
            return
        }
        isAuthenticating = true
        defer { isAuthenticating = false }
        if await authenticator.authenticate(reason: String(localized: "Разблокировать MoneyTalks")) {
            isLocked = false
        }
    }

    /// Включает или выключает блокировку после подтверждения владельца.
    /// - Returns: применилось ли изменение.
    @discardableResult
    public func setEnabled(_ enabled: Bool) async -> Bool {
        guard enabled != isEnabled, !isAuthenticating else { return false }
        if enabled, authenticator.method() == .unavailable { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let reason = enabled
            ? String(localized: "Включить блокировку MoneyTalks")
            : String(localized: "Выключить блокировку MoneyTalks")
        guard await authenticator.authenticate(reason: reason) else { return false }
        isEnabled = enabled
        defaults.set(enabled, forKey: SettingsKey.appLockEnabled)
        return true
    }
}

/// Экран поверх приложения: без сумм и операций, с кнопкой разблокировки, если оно заперто.
struct LockCover: View {
    let lock: AppLock

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.background)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("MoneyTalks")
                    .font(.title2.bold())
                if lock.isLocked {
                    Button {
                        Task { await lock.unlock() }
                    } label: {
                        Text("Разблокировать")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(lock.isAuthenticating)
                }
            }
        }
    }
}

public extension View {
    /// Закрывает содержимое, когда приложение заперто или в переключателе приложений,
    /// и запирает его при уходе в фон.
    func appLock(_ lock: AppLock) -> some View {
        modifier(AppLockModifier(lock: lock))
    }
}

private struct AppLockModifier: ViewModifier {
    let lock: AppLock
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .overlay {
                if lock.shouldCover(scenePhase) {
                    LockCover(lock: lock)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if lock.sceneDidChange(to: phase) {
                    Task { await lock.unlock() }
                }
            }
            .task {
                // Холодный запуск в уже активной сцене: onChange не сработает. Если сцена ещё
                // неактивна, разблокировку запросит первый переход в `.active`.
                if scenePhase == .active {
                    await lock.unlock()
                }
            }
    }
}
