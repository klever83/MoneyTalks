import Foundation

/// Фильтр для выборки операций.
public struct TransactionQuery: Hashable, Sendable {
    public var interval: DateInterval?
    public var accountID: Account.ID?
    public var limit: Int?

    public init(interval: DateInterval? = nil, accountID: Account.ID? = nil, limit: Int? = nil) {
        self.interval = interval
        self.accountID = accountID
        self.limit = limit
    }
}

public protocol AccountRepository: Sendable {
    /// Поток актуального списка счетов: новое значение после каждого изменения в базе.
    func observeAccounts() -> AsyncThrowingStream<[Account], any Error>
    func save(_ account: Account) async throws
    /// Мягкое удаление: запись помечается `deletedAt` (нужно для будущей синхронизации).
    func delete(_ id: Account.ID) async throws
}

public protocol TransactionRepository: Sendable {
    func observeTransactions(_ query: TransactionQuery) -> AsyncThrowingStream<[FinanceTransaction], any Error>
    func transactions(_ query: TransactionQuery) async throws -> [FinanceTransaction]
    func save(_ transactions: [FinanceTransaction]) async throws
    func delete(_ id: FinanceTransaction.ID) async throws
    /// Отпечатки уже сохранённых операций счёта — для дедупликации при импорте.
    func fingerprints(accountID: Account.ID) async throws -> Set<String>
}

public protocol CategoryRepository: Sendable {
    func observeCategories() -> AsyncThrowingStream<[FinanceCategory], any Error>
    func categories() async throws -> [FinanceCategory]
    func save(_ category: FinanceCategory) async throws
}
