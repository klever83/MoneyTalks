import Foundation
import GRDB

extension AppDatabase {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        #if DEBUG && targetEnvironment(simulator)
        // Пока схема меняется часто, в симуляторе база пересоздаётся при изменении миграций.
        // На реальном устройстве никогда: там могут быть настоящие данные.
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
            // Явные колонки схемы v1, а не `CategoryRecord`: запись знает о колонках из более поздних
            // миграций (`isHidden`), которых на этом шаге ещё нет.
            for (index, category) in SystemCategories.all.enumerated() {
                try db.execute(
                    sql: """
                    INSERT INTO categories (id, name, systemKey, systemImage, colorHex, parentID, kind, sortOrder, updatedAt)
                    VALUES (?, ?, ?, ?, ?, NULL, ?, ?, ?)
                    """,
                    arguments: [
                        category.id.rawValue, category.name, category.systemKey, category.systemImage,
                        category.colorHex, category.kind.rawValue, index, category.updatedAt,
                    ]
                )
            }
        }

        migrator.registerMigration("v2-category-rules") { db in
            // Только правила пользователя: встроенные живут в коде (`BuiltInRules`).
            try db.create(table: "categoryRules") { t in
                t.primaryKey("id", .blob)
                // `[CategoryRule.Condition]` в JSON: условия меняются чаще схемы.
                t.column("conditions", .text).notNull()
                t.column("categoryID", .blob).notNull().references("categories", onDelete: .cascade)
                t.column("priority", .integer).notNull().defaults(to: 0)
                t.column("origin", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
            }
        }

        migrator.registerMigration("v3-category-hidden") { db in
            try db.alter(table: "categories") { t in
                t.add(column: "isHidden", .boolean).notNull().defaults(to: false)
            }
        }

        migrator.registerMigration("v4-import-batches") { db in
            try db.create(table: "importBatches") { t in
                t.primaryKey("id", .blob)
                t.column("accountID", .blob).notNull().references("accounts", onDelete: .cascade)
                t.column("bankName", .text).notNull()
                t.column("fileName", .text).notNull()
                t.column("fileHash", .text).indexed()
                t.column("periodStart", .datetime)
                t.column("periodEnd", .datetime)
                t.column("importedAt", .datetime).notNull()
                t.column("transactionCount", .integer).notNull()
                t.column("duplicateCount", .integer).notNull().defaults(to: 0)
                t.column("previousOpeningBalanceMinor", .integer)
                t.column("rolledBackAt", .datetime)
            }
            try db.create(index: "transactions_import_batch", on: "transactions", columns: ["importBatchID"])
        }

        return migrator
    }
}
