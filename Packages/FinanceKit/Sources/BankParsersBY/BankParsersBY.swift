import StatementImport

/// Парсеры белорусских банков.
///
/// Каждый парсер пишется под настоящую выписку-образец, а тесты идут на обезличенных
/// фикстурах той же разметки (реальные выписки в репозиторий не попадают).
public enum BankParsersBY {
    public static let all: [any StatementParser] = [
        PriorbankParser(),
    ]

    public static let belarusbank = BankInfo(id: "by.belarusbank", name: "Беларусбанк", country: "BY")
    public static let alfabank = BankInfo(id: "by.alfabank", name: "Альфа-Банк", country: "BY")
    public static let priorbank = BankInfo(id: "by.priorbank", name: "Приорбанк", country: "BY")
    public static let sberbank = BankInfo(id: "by.sberbank", name: "Сбер Банк", country: "BY")

    public static let banks: [BankInfo] = [belarusbank, alfabank, priorbank, sberbank]
}
