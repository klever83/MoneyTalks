import Domain
import Foundation
import GRDB

/// Перевод ключей «всегда так» (`CategoryRule.Condition.merchantKey`) на текущий
/// `MerchantNormalizer.key`. Правило хранит ключ, а не исходное название, поэтому без перевода
/// оно молча перестаёт совпадать с операциями после изменения функции.
enum MerchantKeyMigration {
    /// Новый ключ берётся по операциям, у которых был старый: у `evropochta minskiy rayon` это
    /// `evropochta`, самый частый, если вариантов несколько. Без таких операций ключ
    /// пересчитывается из самого старого ключа, а пустой результат оставляет правило как было.
    static func migrate(_ db: Database, legacyKey: (String) -> String) throws {
        let records = try CategoryRuleRecord.fetchAll(db)
        let oldKeys = Set(records.compactMap(\.domain).flatMap(\.conditions).compactMap(\.merchantKeyValue))
        guard !oldKeys.isEmpty else { return }

        var counts: [String: [String: Int]] = [:]
        let rows = try Row.fetchCursor(
            db,
            sql: "SELECT merchantRaw, COUNT(*) AS n FROM transactions WHERE deletedAt IS NULL GROUP BY merchantRaw"
        )
        while let row = try rows.next() {
            let raw: String = row["merchantRaw"]
            let old = legacyKey(raw)
            guard oldKeys.contains(old) else { continue }
            let new = MerchantNormalizer.key(raw)
            guard !new.isEmpty else { continue }
            counts[old, default: [:]][new, default: 0] += row["n"] as Int
        }

        func newKey(for old: String) -> String {
            if let best = counts[old]?.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }) {
                return best.key
            }
            let recomputed = MerchantNormalizer.key(old)
            return recomputed.isEmpty ? old : recomputed
        }

        let now = Date()
        for var record in records {
            guard let rule = record.domain else { continue }
            let conditions = rule.conditions.map { condition in
                condition.merchantKeyValue.map { CategoryRule.Condition.merchantKey(newKey(for: $0)) } ?? condition
            }
            guard conditions != rule.conditions else { continue }
            record.conditions = String(decoding: try JSONEncoder().encode(conditions), as: UTF8.self)
            record.updatedAt = now
            try record.update(db)
        }
    }

    /// `MerchantNormalizer.key` до v12, замороженный: по нему записаны ключи старых правил.
    /// Не менять. Следующее изменение ключа — своя миграция с копией текущей функции.
    static func keyV1(_ raw: String) -> String {
        raw.uppercased()
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
            .filter { token in !token.allSatisfy(\.isNumber) && !serviceWordsV1.contains(token) }
            .joined(separator: " ")
            .lowercased()
    }

    private static let serviceWordsV1: Set<String> = [
        "BY", "BLR", "BELARUS", "MINSK", "МИНСК", "BREST", "GRODNO", "GOMEL", "VITEBSK", "MOGILEV",
        "RETAIL", "CH", "DEBIT", "CREDIT", "SDBO", "NO", "FEE", "P2P", "ATM", "CASH", "CARD", "BANK",
        "TRANSFER", "PAYMENT", "FROM", "TO", "POPOLNENIE", "ERIP",
        "ЕРИП", "ОПЛАТА", "ОПЛАТЫ", "УСЛУГ", "УСЛУГИ", "БЕЗНАЛИЧНАЯ", "ПЕРЕВОД", "ПЕРЕВОДА",
        "ЗАЧИСЛЕНИЕ", "СПИСАНИЕ", "ПОПОЛНЕНИЕ", "ПОСТУПЛЕНИЕ", "ВОЗВРАТ", "ОБМЕН", "КОНВЕРСИЯ",
        "СНЯТИЕ", "ПОЛУЧЕНИЕ", "НАЛИЧНЫХ", "КОМИССИЯ", "КАРТЫ", "КАРТУ", "КАРТА", "СЧЁТ", "СЧЕТ", "СЧЕТА",
        "НА", "С", "СО", "ПО", "ЗА", "В", "ОТ",
    ]
}

private extension CategoryRule.Condition {
    var merchantKeyValue: String? {
        if case .merchantKey(let key) = self { key } else { nil }
    }
}
