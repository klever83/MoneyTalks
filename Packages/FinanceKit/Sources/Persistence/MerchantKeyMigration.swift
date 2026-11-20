import Domain
import Foundation
import GRDB

/// Перевод ключей «всегда так» (`CategoryRule.Condition.merchantKey`) с одной версии
/// `MerchantNormalizer.key` на следующую. Правило хранит ключ, а не исходное название, поэтому
/// без перевода оно молча перестаёт совпадать с операциями после изменения функции.
/// Обе версии передаются замороженными копиями, кроме последней (живая функция): тогда старая
/// база проходит v1 → v2 → v3 по шагам.
enum MerchantKeyMigration {
    /// Новый ключ берётся по операциям, у которых был старый: у `evropochta minskiy rayon` это
    /// `evropochta`, самый частый, если вариантов несколько. Без таких операций ключ
    /// пересчитывается из самого старого ключа, а пустой результат оставляет правило как было.
    /// После перевода правила с одинаковыми условиями сливаются: остаётся последнее изменённое.
    static func migrate(
        _ db: Database,
        from legacyKey: (String) -> String,
        to currentKey: (String) -> String
    ) throws {
        let records = try CategoryRuleRecord.filter(Column("deletedAt") == nil).fetchAll(db)
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
            let new = currentKey(raw)
            guard !new.isEmpty else { continue }
            counts[old, default: [:]][new, default: 0] += row["n"] as Int
        }

        func newKey(for old: String) -> String {
            if let best = counts[old]?.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }) {
                return best.key
            }
            let recomputed = currentKey(old)
            return recomputed.isEmpty ? old : recomputed
        }

        let now = Date()
        // Условия правила после перевода и время прежнего изменения: по нему выбирается, кто остаётся.
        var migrated: [(record: CategoryRuleRecord, conditions: [CategoryRule.Condition], changedAt: Date)] = []
        for var record in records {
            guard let rule = record.domain else { continue }
            let changedAt = record.updatedAt
            let conditions = rule.conditions.map { condition in
                condition.merchantKeyValue.map { CategoryRule.Condition.merchantKey(newKey(for: $0)) } ?? condition
            }
            if conditions != rule.conditions {
                record.conditions = String(decoding: try JSONEncoder().encode(conditions), as: UTF8.self)
                record.updatedAt = now
                try record.update(db)
            }
            migrated.append((record, conditions, changedAt))
        }

        // `spar` и `geo tbilisi spar` стали одним ключом: два правила с равными условиями
        // разложили бы операции в случайном порядке. Остаётся последнее, что выбрал пользователь.
        let groups = Dictionary(grouping: migrated, by: { $0.conditions })
        for group in groups.values where group.count > 1 {
            let keep = group.max { ($0.changedAt, $0.record.id.uuidString) < ($1.changedAt, $1.record.id.uuidString) }
            for var item in group where item.record.id != keep?.record.id {
                item.record.deletedAt = now
                item.record.updatedAt = now
                try item.record.update(db)
            }
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
