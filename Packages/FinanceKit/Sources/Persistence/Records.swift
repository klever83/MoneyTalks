import Domain
import Foundation
import GRDB

// Записи GRDB живут только внутри Persistence; наружу отдаются доменные структуры.

struct AccountRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "accounts"

    var id: UUID
    var name: String
    var kind: String
    var currencyCode: String
    var currencyDigits: Int
    var bankID: String?
    var maskedNumber: String?
    var openingBalanceMinor: Int64
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(_ account: Account) {
        id = account.id.rawValue
        name = account.name
        kind = account.kind.rawValue
        currencyCode = account.currency.code
        currencyDigits = account.currency.minorUnitDigits
        bankID = account.bankID
        maskedNumber = account.maskedNumber
        openingBalanceMinor = account.openingBalance.minorUnits
        createdAt = account.createdAt
        updatedAt = account.updatedAt
        deletedAt = account.deletedAt
    }

    var domain: Account {
        let currency = Currency(code: currencyCode, minorUnitDigits: currencyDigits)
        return Account(
            id: Account.ID(id),
            name: name,
            kind: Account.Kind(rawValue: kind) ?? .current,
            currency: currency,
            bankID: bankID,
            maskedNumber: maskedNumber,
            openingBalance: Money(minorUnits: openingBalanceMinor, currency: currency),
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }
}

struct CategoryRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "categories"

    var id: UUID
    var name: String
    var systemKey: String?
    var systemImage: String
    var colorHex: String
    var parentID: UUID?
    var kind: String
    var sortOrder: Int
    var updatedAt: Date
    var deletedAt: Date?

    init(_ category: FinanceCategory) {
        id = category.id.rawValue
        name = category.name
        systemKey = category.systemKey
        systemImage = category.systemImage
        colorHex = category.colorHex
        parentID = category.parentID?.rawValue
        kind = category.kind.rawValue
        sortOrder = category.sortOrder
        updatedAt = category.updatedAt
        deletedAt = category.deletedAt
    }

    var domain: FinanceCategory {
        FinanceCategory(
            id: FinanceCategory.ID(id),
            name: name,
            systemKey: systemKey,
            systemImage: systemImage,
            colorHex: colorHex,
            parentID: parentID.map { FinanceCategory.ID($0) },
            kind: FinanceCategory.Kind(rawValue: kind) ?? .expense,
            sortOrder: sortOrder,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }
}

struct TransactionRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "transactions"

    var id: UUID
    var accountID: UUID
    var bookedAt: Date
    var amountMinor: Int64
    var currencyCode: String
    var currencyDigits: Int
    var originalAmountMinor: Int64?
    var originalCurrencyCode: String?
    var originalCurrencyDigits: Int?
    var merchantRaw: String
    var merchantNormalized: String
    var mcc: Int?
    var categoryID: UUID?
    var categoryLocked: Bool
    var kind: String
    var transferPairID: UUID?
    var note: String
    var source: String
    var importBatchID: UUID?
    var fingerprint: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(_ transaction: FinanceTransaction) {
        id = transaction.id.rawValue
        accountID = transaction.accountID.rawValue
        bookedAt = transaction.bookedAt
        amountMinor = transaction.amount.minorUnits
        currencyCode = transaction.amount.currency.code
        currencyDigits = transaction.amount.currency.minorUnitDigits
        originalAmountMinor = transaction.originalAmount?.minorUnits
        originalCurrencyCode = transaction.originalAmount?.currency.code
        originalCurrencyDigits = transaction.originalAmount?.currency.minorUnitDigits
        merchantRaw = transaction.merchantRaw
        merchantNormalized = transaction.merchantNormalized
        mcc = transaction.mcc
        categoryID = transaction.categoryID?.rawValue
        categoryLocked = transaction.categoryLocked
        kind = transaction.kind.rawValue
        transferPairID = transaction.transferPairID
        note = transaction.note
        source = transaction.source.rawValue
        importBatchID = transaction.importBatchID
        fingerprint = transaction.fingerprint
        createdAt = transaction.createdAt
        updatedAt = transaction.updatedAt
        deletedAt = transaction.deletedAt
    }

    var domain: FinanceTransaction {
        let currency = Currency(code: currencyCode, minorUnitDigits: currencyDigits)
        var original: Money?
        if let originalAmountMinor, let originalCurrencyCode {
            original = Money(
                minorUnits: originalAmountMinor,
                currency: Currency(code: originalCurrencyCode, minorUnitDigits: originalCurrencyDigits ?? 2)
            )
        }
        return FinanceTransaction(
            id: FinanceTransaction.ID(id),
            accountID: Account.ID(accountID),
            bookedAt: bookedAt,
            amount: Money(minorUnits: amountMinor, currency: currency),
            originalAmount: original,
            merchantRaw: merchantRaw,
            merchantNormalized: merchantNormalized,
            mcc: mcc,
            categoryID: categoryID.map { FinanceCategory.ID($0) },
            categoryLocked: categoryLocked,
            kind: FinanceTransaction.Kind(rawValue: kind),
            transferPairID: transferPairID,
            note: note,
            source: FinanceTransaction.Source(rawValue: source) ?? .manual,
            importBatchID: importBatchID,
            fingerprint: fingerprint,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }
}

struct CategoryRuleRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "categoryRules"

    var id: UUID
    var conditions: String
    var categoryID: UUID
    var priority: Int
    var origin: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(_ rule: CategoryRule, createdAt: Date, updatedAt: Date) throws {
        id = rule.id.rawValue
        conditions = String(decoding: try JSONEncoder().encode(rule.conditions), as: UTF8.self)
        categoryID = rule.categoryID.rawValue
        priority = rule.priority
        origin = rule.origin.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        deletedAt = nil
    }

    /// `nil`, если условия не читаются (например, записаны более новой версией приложения):
    /// такое правило пропускается, а не роняет категоризацию.
    var domain: CategoryRule? {
        guard let decoded = try? JSONDecoder().decode([CategoryRule.Condition].self, from: Data(conditions.utf8)) else {
            return nil
        }
        return CategoryRule(
            id: CategoryRule.ID(id),
            conditions: decoded,
            categoryID: FinanceCategory.ID(categoryID),
            priority: priority,
            origin: CategoryRule.Origin(rawValue: origin) ?? .user
        )
    }
}
