import Domain
import Foundation
import GRDB
@testable import Persistence
import Testing

@Suite("Перевод ключей «всегда так» на новый ключ мерчанта")
struct MerchantKeyMigrationTests {
    @Test("Старый ключ правила заменяется ключом его операций, другие условия не трогаются")
    func migratesRules() throws {
        let queue = try DatabaseQueue()
        let migrator = AppDatabase.migrator
        try migrator.migrate(queue, upTo: "v11-transfer-declined")

        let account = Account(name: "Карта", kind: .card, currency: .byn)
        let cafes = FinanceCategory.systemID(for: "cafes")
        let raws = [
            "EVROPOCHTA BLR, MINSKIY RAYON", "EVROPOCHTA BLR, MINSKIY RAYON", "Retail GEO TBILISI SPAR",
        ]
        let evropochtaOld = MerchantKeyMigration.keyV1(raws[0])
        #expect(evropochtaOld == "evropochta minskiy rayon")
        // Ключ без операций пересчитывается из самого ключа, пустой результат оставляет как было.
        let rules = [
            CategoryRule(conditions: [.merchantKey(evropochtaOld), .amountSign(.negative)], categoryID: cafes, origin: .user),
            CategoryRule(conditions: [.merchantKey(MerchantKeyMigration.keyV1(raws[2]))], categoryID: cafes, origin: .user),
            CategoryRule(conditions: [.merchantKey("покупка товара gusto")], categoryID: cafes, origin: .user),
            CategoryRule(conditions: [.merchantKey("g")], categoryID: cafes, origin: .user),
            CategoryRule(conditions: [.merchantContains("EVROOPT")], categoryID: cafes, origin: .user),
        ]
        try queue.write { db in
            try AccountRecord(account).insert(db)
            for raw in raws {
                let transaction = FinanceTransaction(
                    accountID: account.id, bookedAt: .now,
                    amount: Money(minorUnits: -100, currency: .byn), merchantRaw: raw, source: .imported
                )
                try TransactionRecord(transaction).insert(db)
            }
            for rule in rules {
                try CategoryRuleRecord(rule, createdAt: .now, updatedAt: .now).insert(db)
            }
        }

        try migrator.migrate(queue)

        let migrated = try queue.read { db in
            Dictionary(uniqueKeysWithValues: try CategoryRuleRecord.fetchAll(db).compactMap(\.domain).map { ($0.id, $0.conditions) })
        }
        #expect(migrated[rules[0].id] == [.merchantKey("evropochta"), .amountSign(.negative)])
        #expect(migrated[rules[1].id] == [.merchantKey("spar")])
        #expect(migrated[rules[2].id] == [.merchantKey("gusto")])
        #expect(migrated[rules[3].id] == [.merchantKey("g")])
        #expect(migrated[rules[4].id] == [.merchantContains("EVROOPT")])
    }

    @Test("Правила, совпавшие после перевода ключа, сливаются: остаётся последнее изменённое")
    func mergesDuplicates() throws {
        let queue = try DatabaseQueue()
        let migrator = AppDatabase.migrator
        try migrator.migrate(queue, upTo: "v11-transfer-declined")

        let account = Account(name: "Карта", kind: .card, currency: .byn)
        let cafes = FinanceCategory.systemID(for: "cafes")
        let groceries = FinanceCategory.systemID(for: "groceries")
        let minsk = CategoryRule(conditions: [.merchantKey("spar")], categoryID: cafes, origin: .user)
        let tbilisi = CategoryRule(conditions: [.merchantKey("geo tbilisi spar")], categoryID: groceries, origin: .user)
        try queue.write { db in
            try AccountRecord(account).insert(db)
            let transaction = FinanceTransaction(
                accountID: account.id, bookedAt: .now,
                amount: Money(minorUnits: -100, currency: .byn), merchantRaw: "Retail GEO TBILISI SPAR", source: .imported
            )
            try TransactionRecord(transaction).insert(db)
            try CategoryRuleRecord(minsk, createdAt: .now, updatedAt: Date(timeIntervalSince1970: 1_000)).insert(db)
            try CategoryRuleRecord(tbilisi, createdAt: .now, updatedAt: Date(timeIntervalSince1970: 2_000)).insert(db)
        }

        try migrator.migrate(queue)

        let live = try queue.read { db in
            try CategoryRuleRecord.filter(Column("deletedAt") == nil).fetchAll(db).compactMap(\.domain)
        }
        #expect(live.count == 1)
        #expect(live.first?.id == tbilisi.id)
        #expect(live.first?.conditions == [.merchantKey("spar")])
        #expect(live.first?.categoryID == groceries)
    }

    @Test("v13 переводит ключи v12: код страны внутри названия больше не режет его")
    func migratesFromV12() throws {
        let queue = try DatabaseQueue()
        let migrator = AppDatabase.migrator
        try migrator.migrate(queue, upTo: "v12-merchant-key-place")

        let account = Account(name: "Карта", kind: .card, currency: .byn)
        let raw = "SUPER TUR BLR, MINSK"
        #expect(MerchantKeyV2.key(raw) == "super")
        let rule = CategoryRule(conditions: [.merchantKey(MerchantKeyV2.key(raw))], categoryID: FinanceCategory.systemID(for: "travel"), origin: .user)
        try queue.write { db in
            try AccountRecord(account).insert(db)
            let transaction = FinanceTransaction(
                accountID: account.id, bookedAt: .now,
                amount: Money(minorUnits: -100, currency: .byn), merchantRaw: raw, source: .imported
            )
            try TransactionRecord(transaction).insert(db)
            try CategoryRuleRecord(rule, createdAt: .now, updatedAt: .now).insert(db)
        }

        try migrator.migrate(queue)

        let conditions = try queue.read { db in
            try CategoryRuleRecord.fetchOne(db, key: rule.id.rawValue)?.domain?.conditions
        }
        #expect(conditions == [.merchantKey("super tur")])
    }
}
