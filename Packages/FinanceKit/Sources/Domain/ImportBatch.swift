import Foundation

/// Партия импорта: одна загруженная выписка. Её операции помечены `importBatchID`,
/// и партию можно откатить целиком.
public struct ImportBatch: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var accountID: Account.ID
    public var bankName: String
    public var fileName: String
    /// SHA-256 содержимого файла: повторная загрузка того же файла распознаётся до превью.
    public var fileHash: String?
    public var period: DateInterval?
    public var importedAt: Date
    /// Новые операции выписки (без вторых сторон снятия наличных).
    public var transactionCount: Int
    /// Строки, отброшенные как уже импортированные.
    public var duplicateCount: Int
    /// Начальный остаток счёта в минимальных единицах его валюты до импорта, если импорт
    /// его заменил (более ранняя выписка): откат возвращает прежний.
    public var previousOpeningBalanceMinor: Int64?
    /// Начальный остаток, который поставил импорт. Откат возвращает прежний, только если остаток
    /// с тех пор не менялся: иначе его поменял более поздний импорт или пользователь, и это значение новее.
    public var appliedOpeningBalanceMinor: Int64?
    /// Импорт создал счёт: при откате можно предложить удалить и его.
    public var createdAccount: Bool
    public var rolledBackAt: Date?

    public init(
        id: UUID,
        accountID: Account.ID,
        bankName: String,
        fileName: String,
        fileHash: String? = nil,
        period: DateInterval? = nil,
        importedAt: Date = .now,
        transactionCount: Int,
        duplicateCount: Int = 0,
        previousOpeningBalanceMinor: Int64? = nil,
        appliedOpeningBalanceMinor: Int64? = nil,
        createdAccount: Bool = false,
        rolledBackAt: Date? = nil
    ) {
        self.id = id
        self.accountID = accountID
        self.bankName = bankName
        self.fileName = fileName
        self.fileHash = fileHash
        self.period = period
        self.importedAt = importedAt
        self.transactionCount = transactionCount
        self.duplicateCount = duplicateCount
        self.previousOpeningBalanceMinor = previousOpeningBalanceMinor
        self.appliedOpeningBalanceMinor = appliedOpeningBalanceMinor
        self.createdAccount = createdAccount
        self.rolledBackAt = rolledBackAt
    }
}
