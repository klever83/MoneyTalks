import Foundation
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
        BSBBankParser(),
        BelinvestbankParser(),
        OplatiParser(),
    ]

    public static let belarusbank = BankInfo(id: "by.belarusbank", name: "Беларусбанк", country: "BY")
    public static let alfabank = BankInfo(id: "by.alfabank", name: "Альфа-Банк", country: "BY")
    public static let priorbank = BankInfo(id: "by.priorbank", name: "Приорбанк", country: "BY")
    public static let bnb = BankInfo(id: "by.bnb", name: "БНБ-Банк", country: "BY")
    public static let bsb = BankInfo(id: "by.bsb", name: "БСБ Банк", country: "BY")
    public static let belinvestbank = BankInfo(id: "by.belinvestbank", name: "Белинвестбанк", country: "BY")
    /// Электронный кошелёк Белинвестбанка: отдельный «банк», чтобы кошелёк не смешивался со счетами карт.
    public static let oplati = BankInfo(id: "by.oplati", name: "Оплати", country: "BY")

    /// Банки, выписки которых читаются: список на экране импорта. Берётся из парсеров,
    /// чтобы в нём не оказалось банка без парсера.
    public static var banks: [BankInfo] {
        var seen: Set<String> = []
        return all.map(\.bank).filter { seen.insert($0.id).inserted }
    }

    /// Предупреждение об операциях, которые банк ещё не провёл и которые парсер не импортирует.
    /// Подсказывает, с какой даты выгрузить следующую выписку: если она начнётся позже, чем эти
    /// операции проведут, они не попадут ни в одну выписку. Пересечение периодов безопасно, дубли отсеются.
    static func pendingWarning(_ title: String, count: Int, periodEnd: Date?) -> ParseWarning {
        var message = "\(title) не импортированы (\(count)): они появятся после проведения"
        if let periodEnd {
            let day = BYDate.calendar.dateComponents([.year, .month, .day], from: periodEnd)
            message += String(format: ". Следующую выписку выгрузите начиная с %02d.%02d.%04d", day.day ?? 0, day.month ?? 0, day.year ?? 0)
        }
        return ParseWarning(line: nil, message: message)
    }

    /// Предупреждение, когда в выписке не нашлось остатков или оборотов для сверки.
    static let noCheckWarning = ParseWarning(line: nil, message: "Остатки или обороты в выписке не найдены, сверка не выполнена")
}
