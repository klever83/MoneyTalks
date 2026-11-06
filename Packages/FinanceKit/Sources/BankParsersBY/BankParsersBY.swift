import StatementImport

/// Парсеры белорусских банков.
///
/// Пусто, пока нет реальных выписок: каждый парсер пишется под настоящий файл-образец
/// и покрывается golden-тестами (см. README в корне репозитория).
/// Очередь: Беларусбанк, Альфа-Банк, Приорбанк, Сбер Банк.
public enum BankParsersBY {
    public static let all: [any StatementParser] = []

    public static let banks: [BankInfo] = [
        BankInfo(id: "by.belarusbank", name: "Беларусбанк", country: "BY"),
        BankInfo(id: "by.alfabank", name: "Альфа-Банк", country: "BY"),
        BankInfo(id: "by.priorbank", name: "Приорбанк", country: "BY"),
        BankInfo(id: "by.sberbank", name: "Сбер Банк", country: "BY"),
    ]
}
