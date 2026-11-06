import Foundation

/// Даты в выписках белорусских банков: всегда по времени Минска.
enum BYDate {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Minsk") ?? .current
        return calendar
    }

    /// `dd.MM.yyyy`
    static func date(_ text: String) -> Date? {
        guard let match = text.wholeMatch(of: /(\d{2})\.(\d{2})\.(\d{4})/) else { return nil }
        return calendar.date(from: DateComponents(year: Int(match.3), month: Int(match.2), day: Int(match.1)))
    }

    /// `dd.MM.yyyy HH:mm` или `dd.MM.yyyy HH:mm:ss`
    static func dateTime(_ text: String) -> Date? {
        guard let match = text.wholeMatch(of: /(\d{2})\.(\d{2})\.(\d{4}) (\d{2}):(\d{2})(?::(\d{2}))?/) else { return nil }
        return calendar.date(from: DateComponents(
            year: Int(match.3), month: Int(match.2), day: Int(match.1),
            hour: Int(match.4), minute: Int(match.5), second: match.6.flatMap { Int($0) } ?? 0
        ))
    }
}
