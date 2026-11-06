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

    /// Разделитель по первой строке: `;`, `,` или табуляция. По умолчанию `;`.
    public static func detectDelimiter(in text: String) -> Character {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        var counts: [Character: Int] = [";": 0, ",": 0, "\t": 0]
        var inQuotes = false
        for character in firstLine {
            if character == "\"" { inQuotes.toggle() }
            if !inQuotes, counts[character] != nil { counts[character, default: 0] += 1 }
        }
        let best = counts.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key != ";" : lhs.value < rhs.value
        }
        guard let best, best.value > 0 else { return ";" }
        return best.key
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
