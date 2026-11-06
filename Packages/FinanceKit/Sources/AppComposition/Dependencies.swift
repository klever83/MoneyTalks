import BankParsersBY
import Domain
import Persistence
import StatementImport

/// Все зависимости приложения в одном месте. Фичи получают только нужные им протоколы.
public struct Dependencies: Sendable {
    public let accounts: any AccountRepository
    public let transactions: any TransactionRepository
    public let categories: any CategoryRepository
    public let parserRegistry: ParserRegistry

    init(database: AppDatabase) {
        accounts = GRDBAccountRepository(database: database)
        transactions = GRDBTransactionRepository(database: database)
        categories = GRDBCategoryRepository(database: database)
        parserRegistry = ParserRegistry(parsers: BankParsersBY.all)
    }

    /// Рабочая база на диске.
    public static func live() throws -> Dependencies {
        Dependencies(database: try AppDatabase.onDisk())
    }

    /// База в памяти: для превью и UI-тестов.
    public static func inMemory() throws -> Dependencies {
        Dependencies(database: try AppDatabase.inMemory())
    }
}
