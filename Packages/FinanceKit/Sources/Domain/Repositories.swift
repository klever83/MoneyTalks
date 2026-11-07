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
    /// Идентификаторы удалённых счетов: новый счёт не должен получить такой же и «воскресить» удалённый.
    func deletedAccountIDs() async throws -> Set<Account.ID>
}

public protocol TransactionRepository: Sendable {
    func observeTransactions(_ query: TransactionQuery) -> AsyncThrowingStream<[FinanceTransaction], any Error>
    func transactions(_ query: TransactionQuery) async throws -> [FinanceTransaction]
    func save(_ transactions: [FinanceTransaction]) async throws
    func delete(_ id: FinanceTransaction.ID) async throws
    /// Отпечатки операций счёта для дедупликации при импорте, включая удалённые:
    /// удалённая пользователем операция не возвращается при импорте пересекающейся выписки.
    func fingerprints(accountID: Account.ID) async throws -> Set<String>
}

public protocol CategoryRepository: Sendable {
    /// Все неудалённые категории, включая скрытые: скрытые нужны, чтобы показать категорию старых операций.
    func observeCategories() -> AsyncThrowingStream<[FinanceCategory], any Error>
    func categories() async throws -> [FinanceCategory]
    func save(_ category: FinanceCategory) async throws
    /// Удаляет пользовательскую категорию вместе с подкатегориями одной транзакцией базы:
    /// их операции остаются без категории (и без закрепления), правила для них удаляются.
    /// Системную категорию удалить нельзя — только скрыть.
    func delete(_ id: FinanceCategory.ID) async throws
}

public enum CategoryError: Error, Equatable, Sendable {
    case systemCategoryCannotBeDeleted
    /// Подкатегорий только два уровня: родитель должен быть верхнего уровня и того же типа.
    case invalidParent
}

/// Правила категоризации пользователя. Встроенные правила живут в коде (`BuiltInRules`) и сюда не пишутся.
public protocol CategoryRuleRepository: Sendable {
    func rules() async throws -> [CategoryRule]
    func save(_ rule: CategoryRule) async throws
    func delete(_ id: CategoryRule.ID) async throws
}

/// Проставляет категории операциям по правилам.
public protocol TransactionCategorizer: Sendable {
    /// Возвращает те же операции, у которых без категории появилась подсказанная.
    /// Переводы, операции с закреплённой или уже выбранной категорией не меняются.
    func categorize(_ transactions: [FinanceTransaction]) async throws -> [FinanceTransaction]
}

/// Уже сохранённая операция, которая при импорте стала стороной перевода.
public struct TransferLink: Hashable, Sendable {
    public var transactionID: FinanceTransaction.ID
    public var pairID: UUID

    public init(transactionID: FinanceTransaction.ID, pairID: UUID) {
        self.transactionID = transactionID
        self.pairID = pairID
    }
}

public enum ImportCommitError: Error, Equatable, Sendable {
    /// Операция для перевода изменилась или удалена, пока шло превью: импорт откатывается.
    case transactionChanged
}

public protocol ImportRepository: Sendable {
    /// Сохраняет результат импорта одной транзакцией базы: новые счета и операции, а у уже
    /// сохранённых операций точечно отмечает перевод (только тип, пару и категорию, остальное
    /// не трогается). Если такая операция за это время удалена, уже связана или пользователь
    /// закрепил её категорию, бросает
    /// `ImportCommitError.transactionChanged`, и не сохраняется ничего.
    func commitImport(accounts: [Account], transactions: [FinanceTransaction], links: [TransferLink]) async throws
}

public extension AccountRepository {
    /// Реализация по умолчанию для хранилищ без мягкого удаления (превью, тестовые заглушки).
    func deletedAccountIDs() async throws -> Set<Account.ID> { [] }
}
