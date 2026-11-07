import StatementImport

/// Парсеры белорусских банков.
///
/// Каждый парсер пишется под настоящую выписку-образец, а тесты идут на обезличенных
/// фикстурах той же разметки (реальные выписки в репозиторий не попадают).
public enum BankParsersBY {
    public static let all: [any StatementParser] = [
        PriorbankParser(),
        BelarusbankParser(),
        AlfabankParser(),
        BNBBankParser(),
    ]

    public static let belarusbank = BankInfo(id: "by.belarusbank", name: "Беларусбанк", country: "BY")
    public static let alfabank = BankInfo(id: "by.alfabank", name: "Альфа-Банк", country: "BY")
    public static let priorbank = BankInfo(id: "by.priorbank", name: "Приорбанк", country: "BY")
    public static let bnb = BankInfo(id: "by.bnb", name: "БНБ-Банк", country: "BY")

    /// Банки, выписки которых читаются: список на экране импорта. Берётся из парсеров,
    /// чтобы в нём не оказалось банка без парсера.
    public static var banks: [BankInfo] {
        var seen: Set<String> = []
        return all.map(\.bank).filter { seen.insert($0.id).inserted }
    }
}
