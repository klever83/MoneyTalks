import Foundation
import GRDB

extension AppDatabase {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        #if DEBUG
        // Пока схема меняется часто, в отладке база пересоздаётся при изменении миграций.
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1") { db in
            try db.create(table: "accounts") { t in
                t.primaryKey("id", .blob)
                t.column("name", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("currencyCode", .text).notNull()
                t.column("currencyDigits", .integer).notNull()
                t.column("bankID", .text)
                t.column("maskedNumber", .text)
                t.column("openingBalanceMinor", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
            }

            try db.create(table: "categories") { t in
                t.primaryKey("id", .blob)
                t.column("name", .text).notNull()
                t.column("systemKey", .text).unique()
                t.column("systemImage", .text).notNull()
                t.column("colorHex", .text).notNull()
                t.column("parentID", .blob).references("categories", onDelete: .setNull)
                t.column("kind", .text).notNull()
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("updatedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
            }

            try db.create(table: "transactions") { t in
                t.primaryKey("id", .blob)
                t.column("accountID", .blob).notNull().references("accounts", onDelete: .cascade)
                t.column("bookedAt", .datetime).notNull()
                t.column("amountMinor", .integer).notNull()
                t.column("currencyCode", .text).notNull()
                t.column("currencyDigits", .integer).notNull()
                t.column("originalAmountMinor", .integer)
                t.column("originalCurrencyCode", .text)
                t.column("originalCurrencyDigits", .integer)
                t.column("merchantRaw", .text).notNull()
                t.column("merchantNormalized", .text).notNull()
                t.column("mcc", .integer)
                t.column("categoryID", .blob).references("categories", onDelete: .setNull)
                t.column("categoryLocked", .boolean).notNull().defaults(to: false)
                t.column("kind", .text).notNull()
                t.column("transferPairID", .blob)
                t.column("note", .text).notNull().defaults(to: "")
                t.column("source", .text).notNull()
                t.column("importBatchID", .blob)
                t.column("fingerprint", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
            }
            try db.create(index: "transactions_account_date", on: "transactions", columns: ["accountID", "bookedAt"])
            try db.create(index: "transactions_category_date", on: "transactions", columns: ["categoryID", "bookedAt"])
            try db.create(index: "transactions_account_fingerprint", on: "transactions", columns: ["accountID", "fingerprint"])
        }

        migrator.registerMigration("v1-system-categories") { db in
            for (index, category) in SystemCategories.all.enumerated() {
                var category = category
                category.sortOrder = index
                try CategoryRecord(category).insert(db)
            }
        }

        return migrator
    }
}
