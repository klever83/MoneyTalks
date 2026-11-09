import Domain
import Foundation
import GRDB

private let deletedAt = Column("deletedAt")

public struct GRDBAccountRepository: AccountRepository {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func observeAccounts() -> AsyncThrowingStream<[Account], any Error> {
        database.stream(ValueObservation.tracking { db in
            try AccountRecord
                .filter(deletedAt == nil)
                .order(Column("createdAt"))
                .fetchAll(db)
                .map(\.domain)
        })
    }

    public func save(_ account: Account) async throws {
        var account = account
        account.updatedAt = .now
        let record = AccountRecord(account)
        try await database.writer.write { db in
            try record.save(db)
        }
    }

    public func deletedAccountIDs() async throws -> Set<Account.ID> {
        try await database.writer.read { db in
            Set(try AccountRecord
                .filter(deletedAt != nil)
                .select(Column("id"), as: UUID.self)
                .fetchAll(db)
                .map(Account.ID.init))
        }
    }

    public func observeBalances() -> AsyncThrowingStream<[Account.ID: Money], any Error> {
        database.stream(ValueObservation.tracking { db in
            // Операции в другой валюте (если такие попадут на счёт) в остаток не входят:
            // складывать разные валюты без курса нельзя.
            let rows = try Row.fetchAll(db, sql: """
                SELECT a.id, a.currencyCode, a.currencyDigits,
                       a.openingBalanceMinor + COALESCE(SUM(t.amountMinor), 0) AS balanceMinor
                FROM accounts a
                LEFT JOIN transactions t
                    ON t.accountID = a.id AND t.deletedAt IS NULL AND t.currencyCode = a.currencyCode
                WHERE a.deletedAt IS NULL
                GROUP BY a.id
                """)
            var balances: [Account.ID: Money] = [:]
            for row in rows {
                let id: UUID = row["id"]
                let currency = Currency(code: row["currencyCode"], minorUnitDigits: row["currencyDigits"])
                balances[Account.ID(id)] = Money(minorUnits: row["balanceMinor"], currency: currency)
            }
            return balances
        })
    }

    public func delete(_ id: Account.ID) async throws {
        let now = Date.now
        try await database.writer.write { db in
            _ = try AccountRecord
                .filter(key: id.rawValue)
                .updateAll(db, deletedAt.set(to: now), Column("updatedAt").set(to: now))
            // Операции удалённого счёта не должны оставаться в ленте и в итогах.
            _ = try TransactionRecord
                .filter(Column("accountID") == id.rawValue && deletedAt == nil)
                .updateAll(db, deletedAt.set(to: now), Column("updatedAt").set(to: now))
        }
    }
}

public struct GRDBTransactionRepository: TransactionRepository {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func observeTransactions(_ query: TransactionQuery) -> AsyncThrowingStream<[FinanceTransaction], any Error> {
        database.stream(ValueObservation.tracking { db in
            try Self.request(for: query).fetchAll(db).map(\.domain)
        })
    }

    public func transactions(_ query: TransactionQuery) async throws -> [FinanceTransaction] {
        try await database.writer.read { db in
            try Self.request(for: query).fetchAll(db).map(\.domain)
        }
    }

    public func save(_ transactions: [FinanceTransaction]) async throws {
        let now = Date.now
        let records = transactions.map { transaction in
            var transaction = transaction
            transaction.updatedAt = now
            return TransactionRecord(transaction)
        }
        try await database.writer.write { db in
            for record in records {
                try record.save(db)
            }
        }
    }

    public func delete(_ id: FinanceTransaction.ID) async throws {
        let now = Date.now
        try await database.writer.write { db in
            _ = try TransactionRecord
                .filter(key: id.rawValue)
                .updateAll(db, deletedAt.set(to: now), Column("updatedAt").set(to: now))
        }
    }

    public func fingerprints(accountID: Account.ID) async throws -> Set<String> {
        try await database.writer.read { db in
            try TransactionRecord
                .filter(Column("accountID") == accountID.rawValue && Column("fingerprint") != nil)
                .select(Column("fingerprint"), as: String.self)
                .fetchSet(db)
        }
    }

    private static func request(for query: TransactionQuery) -> QueryInterfaceRequest<TransactionRecord> {
        var request = TransactionRecord.filter(deletedAt == nil)
        if let accountID = query.accountID {
            request = request.filter(Column("accountID") == accountID.rawValue)
        }
        if let interval = query.interval {
            request = request.filter(Column("bookedAt") >= interval.start && Column("bookedAt") < interval.end)
        }
        request = request.order(Column("bookedAt").desc)
        if let limit = query.limit {
            request = request.limit(limit)
        }
        return request
    }
}

public struct GRDBCategoryRepository: CategoryRepository {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func observeCategories() -> AsyncThrowingStream<[FinanceCategory], any Error> {
        database.stream(ValueObservation.tracking { db in
            try Self.request.fetchAll(db).map(\.domain)
        })
    }

    public func categories() async throws -> [FinanceCategory] {
        try await database.writer.read { db in
            try Self.request.fetchAll(db).map(\.domain)
        }
    }

    /// Сохраняет категорию. Подкатегорий два уровня: родитель — неудалённая категория верхнего уровня
    /// того же типа, а у самой категории с родителем не может быть своих подкатегорий.
    public func save(_ category: FinanceCategory) async throws {
        var updated = category
        updated.updatedAt = .now
        let record = CategoryRecord(updated)
        let category = updated
        try await database.writer.write { db in
            if let parentID = category.parentID {
                guard parentID != category.id,
                      let parent = try CategoryRecord.filter(key: parentID.rawValue).filter(deletedAt == nil).fetchOne(db),
                      parent.parentID == nil,
                      parent.kind == category.kind.rawValue,
                      try CategoryRecord.filter(Column("parentID") == category.id.rawValue && deletedAt == nil).fetchCount(db) == 0
                else { throw CategoryError.invalidParent }
            }
            try record.save(db)
        }
    }

    public func delete(_ id: FinanceCategory.ID) async throws {
        let now = Date.now
        try await database.writer.write { db in
            guard let category = try CategoryRecord.fetchOne(db, key: id.rawValue), category.deletedAt == nil else { return }
            guard category.systemKey == nil else { throw CategoryError.systemCategoryCannotBeDeleted }
            let ids = [id.rawValue] + (try CategoryRecord
                .filter(Column("parentID") == id.rawValue && deletedAt == nil)
                .select(Column("id"), as: UUID.self)
                .fetchAll(db))
            _ = try CategoryRecord
                .filter(keys: ids)
                .updateAll(db, deletedAt.set(to: now), Column("updatedAt").set(to: now))
            // Операции остаются без категории и без закрепления: правила смогут подобрать новую.
            _ = try TransactionRecord
                .filter(ids.contains(Column("categoryID")))
                .updateAll(
                    db,
                    Column("categoryID").set(to: nil),
                    Column("categoryLocked").set(to: false),
                    Column("updatedAt").set(to: now)
                )
            _ = try CategoryRuleRecord
                .filter(ids.contains(Column("categoryID")) && deletedAt == nil)
                .updateAll(db, deletedAt.set(to: now), Column("updatedAt").set(to: now))
        }
    }

    private static var request: QueryInterfaceRequest<CategoryRecord> {
        CategoryRecord
            .filter(deletedAt == nil)
            .order(Column("kind"), Column("sortOrder"))
    }
}

public struct GRDBCategoryRuleRepository: CategoryRuleRepository {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func rules() async throws -> [CategoryRule] {
        try await database.writer.read { db in
            try CategoryRuleRecord
                .filter(deletedAt == nil)
                .order(Column("createdAt"))
                .fetchAll(db)
                .compactMap(\.domain)
        }
    }

    public func save(_ rule: CategoryRule) async throws {
        let now = Date.now
        try await database.writer.write { db in
            let createdAt = try CategoryRuleRecord.fetchOne(db, key: rule.id.rawValue)?.createdAt ?? now
            try CategoryRuleRecord(rule, createdAt: createdAt, updatedAt: now).save(db)
        }
    }

    public func delete(_ id: CategoryRule.ID) async throws {
        let now = Date.now
        try await database.writer.write { db in
            _ = try CategoryRuleRecord
                .filter(key: id.rawValue)
                .updateAll(db, deletedAt.set(to: now), Column("updatedAt").set(to: now))
        }
    }
}

public struct GRDBImportRepository: ImportRepository {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func commitImport(accounts: [Account], transactions: [FinanceTransaction], links: [TransferLink]) async throws {
        let now = Date.now
        let accountRecords = accounts.map { account in
            var account = account
            account.updatedAt = now
            return AccountRecord(account)
        }
        let transactionRecords = transactions.map { transaction in
            var transaction = transaction
            transaction.updatedAt = now
            return TransactionRecord(transaction)
        }
        try await database.writer.write { db in
            for record in accountRecords {
                try record.save(db)
            }
            for record in transactionRecords {
                try record.save(db)
            }
            for link in links {
                let changed = try TransactionRecord
                    .filter(key: link.transactionID.rawValue)
                    .filter(deletedAt == nil && Column("transferPairID") == nil && Column("categoryLocked") == false)
                    .updateAll(
                        db,
                        Column("kind").set(to: FinanceTransaction.Kind.transfer.rawValue),
                        Column("transferPairID").set(to: link.pairID),
                        Column("categoryID").set(to: nil),
                        Column("updatedAt").set(to: now)
                    )
                guard changed == 1 else { throw ImportCommitError.transactionChanged }
            }
        }
    }
}
