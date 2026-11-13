import CryptoKit
import Domain
import Foundation

/// Отпечатки операций, чтобы повторный импорт той же или пересекающейся выписки не создавал дублей.
public enum ImportDeduplicator {
    /// Отпечаток строки. Если банк дал свой идентификатор, используем его.
    /// Иначе хэш от счёта, времени, суммы, описания и порядкового номера среди одинаковых строк
    /// (два кофе по 5 BYN в одной кофейне за день — это две разные операции).
    /// У операции в обработке свой префикс: проведённая версия с теми же полями не должна
    /// считаться её дублем, она заменяет холд (см. `HoldMatcher`).
    public static func fingerprint(for row: ParsedRow, accountID: Account.ID, occurrence: Int) -> String {
        let base = postedFingerprint(for: row, accountID: accountID, occurrence: occurrence)
        return row.isPending ? "p" + base : base
    }

    private static func postedFingerprint(for row: ParsedRow, accountID: Account.ID, occurrence: Int) -> String {
        if let reference = row.bankReference, !reference.isEmpty {
            // Банк может дать один номер нескольким строкам (операция и её комиссия): различаем по повтору.
            return occurrence == 0 ? "ref:\(reference)" : "ref:\(reference)#\(occurrence)"
        }
        let key = [
            accountID.rawValue.uuidString,
            String(Int64(row.bookedAt.timeIntervalSince1970)),
            String(row.amount.minorUnits),
            row.amount.currency.code,
            row.description.lowercased().filter { !$0.isWhitespace },
            String(occurrence),
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(key.utf8))
        return "h:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Отпечатки для всех строк выписки с учётом повторов.
    public static func fingerprints(for rows: [ParsedRow], accountID: Account.ID) -> [String] {
        var seen: [String: Int] = [:]
        return rows.map { row in
            let base = fingerprint(for: row, accountID: accountID, occurrence: 0)
            let occurrence = seen[base, default: 0]
            seen[base] = occurrence + 1
            return occurrence == 0 ? base : fingerprint(for: row, accountID: accountID, occurrence: occurrence)
        }
    }

    /// Делит строки на новые и уже импортированные.
    public static func split(
        _ rows: [ParsedRow],
        accountID: Account.ID,
        existing: Set<String>
    ) -> (new: [(row: ParsedRow, fingerprint: String)], duplicates: [ParsedRow]) {
        var new: [(row: ParsedRow, fingerprint: String)] = []
        var duplicates: [ParsedRow] = []
        for (row, fingerprint) in zip(rows, fingerprints(for: rows, accountID: accountID)) {
            if existing.contains(fingerprint) {
                duplicates.append(row)
            } else {
                new.append((row, fingerprint))
            }
        }
        return (new, duplicates)
    }
}
