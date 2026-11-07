/// Признаки перевода между счетами в описании операции. Общие для поиска пар переводов
/// (`TransferMatcher`) и для «всегда так», которое на переводах не предлагается.
public enum TransferWords {
    public static let all = [
        "перевод", "p2p", "пополнение", "поступление на контракт", "payment from", "обмен", "конверс",
        "transfer", "popolnenie",
    ]

    public static func appear(in text: String) -> Bool {
        let text = text.lowercased()
        return all.contains { text.contains($0) }
    }
}
