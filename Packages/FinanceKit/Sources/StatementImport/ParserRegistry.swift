/// Выбирает парсер по содержимому файла.
public struct ParserRegistry: Sendable {
    public let parsers: [any StatementParser]
    /// Ниже этого порога автоопределение не срабатывает и пользователь выбирает банк вручную.
    public let threshold: Double

    public init(parsers: [any StatementParser], threshold: Double = 0.5) {
        self.parsers = parsers
        self.threshold = threshold
    }

    public func bestMatch(for document: StatementDocument) -> (any StatementParser)? {
        parsers
            .filter { $0.formats.contains(document.format) }
            .map { (parser: $0, score: $0.confidence(for: document)) }
            .filter { $0.score >= threshold }
            .max { $0.score < $1.score }?
            .parser
    }
}
