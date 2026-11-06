import CryptoKit
import Foundation

extension UUID {
    /// UUID версии 5 (RFC 9562): один и тот же для одинаковых `name` и `namespace` на любом устройстве.
    public init(v5 name: String, namespace: UUID) {
        var input = withUnsafeBytes(of: namespace.uuid) { Array($0) }
        input.append(contentsOf: name.utf8)
        var bytes = Array(Insecure.SHA1.hash(data: input).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // версия 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // вариант RFC
        self = bytes.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
    }
}

extension FinanceCategory {
    /// Пространство имён для ID системных категорий. Не менять: эти ID записаны в базы пользователей
    /// и на них ссылаются встроенные правила категоризации.
    private static let systemNamespace = UUID(uuidString: "B890F4A2-2C35-456A-95DD-A93374676493")!

    /// Стабильный ID системной категории по её `systemKey`, одинаковый на всех устройствах.
    public static func systemID(for systemKey: String) -> ID {
        ID(UUID(v5: systemKey, namespace: systemNamespace))
    }
}
