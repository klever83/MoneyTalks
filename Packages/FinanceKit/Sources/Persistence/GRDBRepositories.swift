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

    public func delete(_ id: Account.ID) async throws {
        let now = Date.now
        try await database.writer.write { db in
            _ = try AccountRecord
                .filter(key: id.rawValue)
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
                .filter(Column("accountID") == accountID.rawValue && Column("fingerprint") != nil && deletedAt == nil)
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

    public func save(_ category: FinanceCategory) async throws {
        var category = category
        category.updatedAt = .now
        let record = CategoryRecord(category)
        try await database.writer.write { db in
            try record.save(db)
        }
    }

    private static var request: QueryInterfaceRequest<CategoryRecord> {
        CategoryRecord
            .filter(deletedAt == nil)
            .order(Column("kind"), Column("sortOrder"))
    }
}
