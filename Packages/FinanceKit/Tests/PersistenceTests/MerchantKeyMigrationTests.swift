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
}
