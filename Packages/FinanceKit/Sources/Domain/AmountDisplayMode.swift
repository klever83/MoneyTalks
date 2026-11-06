/// Как показывать итоги, когда у пользователя несколько валют.
public enum AmountDisplayMode: Hashable, Sendable {
    /// Всё пересчитывается в основную валюту по курсу НБ РБ на дату операции.
    case converted(to: Currency)
    /// Итоги отдельно по каждой валюте, без пересчёта.
    case perCurrency
}
