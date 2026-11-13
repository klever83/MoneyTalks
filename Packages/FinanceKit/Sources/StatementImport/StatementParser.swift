import Domain
import Foundation

public enum StatementFormat: String, Sendable, Hashable, CaseIterable {
    case csv, xlsx, pdf
}

/// Файл выписки, уже прочитанный в таблицу (CSV/XLSX) или в текст с координатами (PDF).
public struct StatementDocument: Sendable {
    public enum Content: Sendable {
        case table([[String]])
        /// PDF: строки и слова с координатами, из них парсер банка собирает таблицу (`TableExtractor`).
        case layout(TextLayout)
    }

    public var fileName: String
    public var format: StatementFormat
    public var content: Content

    public init(fileName: String, format: StatementFormat, content: Content) {
        self.fileName = fileName
        self.format = format
        self.content = content
    }
}

public struct ParserID: Hashable, Sendable, RawRepresentable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
}

public struct BankInfo: Hashable, Sendable {
    /// Например `by.belarusbank`.
    public let id: String
    public let name: String
    /// ISO 3166-1 alpha-2, например `BY`.
    public let country: String

    public init(id: String, name: String, country: String) {
        self.id = id
        self.name = name
        self.country = country
    }
}

/// Что выписка говорит о счёте: по этому ищем счёт в приложении или предлагаем создать новый.
public struct AccountHint: Hashable, Sendable {
    public var maskedNumber: String?
    public var currency: Currency?

    public init(maskedNumber: String? = nil, currency: Currency? = nil) {
        self.maskedNumber = maskedNumber
        self.currency = currency
    }
}

/// Строка выписки: уже типизированная, но ещё не привязанная к счёту и категории.
public struct ParsedRow: Hashable, Sendable {
    public var bookedAt: Date
    /// Сумма в валюте счёта со знаком: расход отрицательный.
    public var amount: Money
    public var originalAmount: Money?
    public var description: String
    public var mcc: Int?
    /// Идентификатор операции в банке, если выписка его содержит.
    public var bankReference: String?
    /// Банк ещё не провёл операцию (холд): сумма при проведении может измениться.
    public var isPending: Bool

    public init(
        bookedAt: Date,
        amount: Money,
        originalAmount: Money? = nil,
        description: String,
        mcc: Int? = nil,
        bankReference: String? = nil,
        isPending: Bool = false
    ) {
        self.bookedAt = bookedAt
        self.amount = amount
        self.originalAmount = originalAmount
        self.description = description
        self.mcc = mcc
        self.bankReference = bankReference
        self.isPending = isPending
    }
}

public struct ParseWarning: Hashable, Sendable {
    public var line: Int?
    public var message: String

    public init(line: Int?, message: String) {
        self.line = line
        self.message = message
    }
}

public struct ParsedStatement: Sendable {
    public var accountHint: AccountHint
    public var period: DateInterval?
    public var openingBalance: Money?
    public var closingBalance: Money?
    public var rows: [ParsedRow]
    /// Строки, которые не удалось разобрать: показываем пользователю в превью импорта.
    public var warnings: [ParseWarning]

    public init(
        accountHint: AccountHint,
        period: DateInterval? = nil,
        openingBalance: Money? = nil,
        closingBalance: Money? = nil,
        rows: [ParsedRow],
        warnings: [ParseWarning] = []
    ) {
        self.accountHint = accountHint
        self.period = period
        self.openingBalance = openingBalance
        self.closingBalance = closingBalance
        self.rows = rows
        self.warnings = warnings
    }
}

public enum ParseError: Error, Equatable, Sendable {
    case unsupportedFormat
    case missingColumn(String)
    case invalidValue(line: Int, field: String, value: String)
}

/// Парсер выписки одного банка в одном формате. Только читает документ и не трогает базу.
public protocol StatementParser: Sendable {
    var id: ParserID { get }
    var bank: BankInfo { get }
    var formats: Set<StatementFormat> { get }

    /// Насколько документ похож на выписку этого банка: от 0 до 1. Должно быть быстрым.
    func confidence(for document: StatementDocument) -> Double

    func parse(_ document: StatementDocument) throws(ParseError) -> ParsedStatement
}
