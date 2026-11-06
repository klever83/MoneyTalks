import CoreGraphics
import Foundation

/// Собирает таблицу выписки из строк `TextLayout`.
///
/// Колонки находит по вертикальным просветам между словами, строки таблицы по «якорю»:
/// строке, где есть признак новой операции (обычно дата в первой колонке).
/// Многострочные ячейки склеиваются, причём неважно, выровнены они по верху или по центру строки.
public enum TableExtractor {
    /// Границы колонок: середины просветов, которые не пересекает ни одно слово ни в одной строке.
    /// - Parameter minGap: просвет уже этого не считается границей.
    public static func columnBoundaries(for lines: [TextLine], minGap: CGFloat = 3) -> [CGFloat] {
        let spans = lines
            .flatMap(\.words)
            .map { ($0.frame.minX, $0.frame.maxX) }
            .sorted { $0.0 < $1.0 }
        guard var current = spans.first else { return [] }
        var boundaries: [CGFloat] = []
        for span in spans.dropFirst() {
            if span.0 - current.1 >= minGap {
                boundaries.append((current.1 + span.0) / 2)
                current = span
            } else {
                current.1 = max(current.1, span.1)
            }
        }
        return boundaries
    }

    /// Текст строки, разложенный по колонкам: слово попадает в колонку по своей середине.
    public static func cells(of line: TextLine, boundaries: [CGFloat]) -> [String] {
        var cells = Array(repeating: [String](), count: boundaries.count + 1)
        for word in line.words.sorted(by: { $0.frame.minX < $1.frame.minX }) {
            let column = boundaries.firstIndex { word.frame.midX < $0 } ?? boundaries.count
            cells[column].append(word.text)
        }
        return cells.map { $0.joined(separator: " ") }
    }

    /// Строки таблицы. Каждая строка начинается с якоря (`isAnchor`), строки текста между двумя
    /// якорями делятся по самому большому вертикальному просвету: что выше, относится к верхней
    /// операции, что ниже, к нижней. Строки до первого якоря относятся к первому, после последнего
    /// к последнему, поэтому передавайте только строки самой таблицы, без шапки и итогов.
    public static func rows(
        _ lines: [TextLine],
        boundaries: [CGFloat],
        isAnchor: ([String]) -> Bool
    ) -> [[String]] {
        let sorted = lines.sorted { $0.frame.minY < $1.frame.minY }
        let cells = sorted.map { self.cells(of: $0, boundaries: boundaries) }
        let anchors = cells.indices.filter { isAnchor(cells[$0]) }
        guard let first = anchors.first, let last = anchors.last else { return [] }

        // Для каждой строки текста — индекс якоря, к которому она относится.
        var owner = Array(repeating: 0, count: sorted.count)
        for index in 0...first { owner[index] = first }
        for index in last..<sorted.count { owner[index] = last }
        for (upper, lower) in zip(anchors, anchors.dropFirst()) {
            var split = upper + 1
            var widest: CGFloat = -.infinity
            for index in (upper + 1)...lower {
                let gap = sorted[index].frame.minY - sorted[index - 1].frame.maxY
                // При равных просветах берём нижний: продолжение ячеек, выровненных по верху.
                if gap >= widest - 0.5 {
                    widest = gap
                    split = index
                }
            }
            for index in upper..<split { owner[index] = upper }
            for index in split...lower { owner[index] = lower }
        }

        return anchors.map { anchor in
            var row = Array(repeating: [String](), count: boundaries.count + 1)
            for index in sorted.indices where owner[index] == anchor {
                for (column, text) in cells[index].enumerated() where !text.isEmpty {
                    row[column].append(text)
                }
            }
            return row.map { $0.joined(separator: " ") }
        }
    }
}
