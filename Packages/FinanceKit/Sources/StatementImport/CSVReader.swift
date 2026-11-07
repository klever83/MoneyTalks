import Foundation

/// Чтение CSV-выписок: кодировка, разделитель, кавычки.
public enum CSVReader {
    /// Белорусские банки нередко отдают CSV в Windows-1251, поэтому пробуем UTF-8, затем её.
    public static func decode(_ data: Data) -> String? {
        if var text = String(data: data, encoding: .utf8) {
            if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
            return text
        }
        return String(data: data, encoding: .windowsCP1251)
    }

    /// Кандидаты в фиксированном порядке: при равных оценках выигрывает тот, что раньше.
    static let delimiterCandidates: [Character] = [";", ",", "\t"]

    /// Разделитель по первым 20 непустым строкам: `;`, `,` или табуляция. По умолчанию `;`.
    ///
    /// У настоящего разделителя количество в строке стабильно (одинаковое число колонок),
    /// а запятая в суммах вроде `12,50` или в описаниях скачет от строки к строке.
    /// Поэтому для каждого кандидата берём самое частое ненулевое количество в строке
    /// и считаем, в скольких строках оно встречается.
    public static func detectDelimiter(in text: String) -> Character {
        let lines = text.split(whereSeparator: \.isNewline)
            .lazy
            .filter { !$0.allSatisfy(\.isWhitespace) }
            .prefix(20)
        let perLine = Array(lines).map { counts(in: $0) }

        var best: (delimiter: Character, lines: Int, columns: Int)?
        for candidate in delimiterCandidates {
            var frequency: [Int: Int] = [:]
            for lineCounts in perLine {
                let count = lineCounts[candidate, default: 0]
                if count > 0 { frequency[count, default: 0] += 1 }
            }
            // Самое частое количество; при равенстве — большее (больше колонок).
            guard let mode = frequency.max(by: { ($0.value, $0.key) < ($1.value, $1.key) }) else { continue }
            if let current = best, (mode.value, mode.key) <= (current.lines, current.columns) { continue }
            best = (candidate, mode.value, mode.key)
        }
        return best?.delimiter ?? ";"
    }

    /// Количество кандидатов в строке вне кавычек.
    private static func counts(in line: Substring) -> [Character: Int] {
        var counts: [Character: Int] = [:]
        var inQuotes = false
        for character in line {
            if character == "\"" {
                inQuotes.toggle()
            } else if !inQuotes, delimiterCandidates.contains(character) {
                counts[character, default: 0] += 1
            }
        }
        return counts
    }

    public static func parse(_ text: String, delimiter: Character? = nil) -> [[String]] {
        let delimiter = delimiter ?? detectDelimiter(in: text)
        let characters = Array(text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var index = 0

        func finishRow() {
            row.append(field)
            field = ""
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while index < characters.count {
            let character = characters[index]
            if inQuotes {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" {
                inQuotes = true
            } else if character == delimiter {
                row.append(field)
                field = ""
            } else if character.isNewline {
                finishRow()
            } else {
                field.append(character)
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty { finishRow() }
        return rows
    }
}
