import CoreGraphics
import Foundation

/// Собирает таблицу выписки из строк `TextLayout`.
///
/// Колонки находит по вертикальным просветам между словами, строки таблицы по «якорю»:
/// строке, где есть признак новой операции (обычно дата в первой колонке).
/// Многострочные ячейки склеиваются, причём неважно, выровнены они по верху или по центру строки.
public enum TableExtractor {
    /// Строки таблицы со всех страниц по порядку: на каждой странице после последней строки шапки
    /// (`isHeader`) и до первой строки колонтитула или итогов (`isFooter`).
    /// Если шапки на странице нет (она не повторяется), строки берутся с начала страницы.
    public static func tableLines(
        in layout: TextLayout,
        isHeader: (TextLine) -> Bool,
        isFooter: (TextLine) -> Bool
    ) -> [TextLine] {
        layout.pages.flatMap { page -> [TextLine] in
            let lines = page.lines
            let start = (lines.lastIndex(where: isHeader) ?? -1) + 1
            let rest = lines[start...]
            let end = rest.firstIndex(where: isFooter) ?? lines.endIndex
            return Array(lines[start..<end])
        }
    }

    /// Границы колонок: середины просветов, которые не пересекает ни одно слово ни в одной строке.
    ///
    /// Запасной вариант: при одной-двух операциях пробелы внутри описания тоже могут стать
    /// границами. Для известного банка надёжнее задать границы по шапке таблицы.
    /// - Parameter minGap: просвет уже этого не считается границей. По умолчанию половина
    ///   типичной высоты строки: шире пробела между словами при любом кегле.
    public static func columnBoundaries(for lines: [TextLine], minGap: CGFloat? = nil) -> [CGFloat] {
        let minGap = minGap ?? (TextLayoutBuilder.median(lines.map(\.frame.height)) ?? 6) * 0.5
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
    /// операции, что ниже, к нижней. При почти равных просветах берётся нижний.
    ///
    /// Строки передаются в порядке чтения, как их отдаёт `tableLines(in:isHeader:isFooter:)`:
    /// сверху вниз, страница за страницей. Переход на новую страницу (координата `y` уменьшилась)
    /// считается самым широким просветом. Строки до первого якоря относятся к первому, после
    /// последнего к последнему, поэтому шапку, колонтитулы и итоги нужно отсеять заранее.
    ///
    /// Ограничение: если ячейки выровнены по центру, а просветы между строками внутри ячейки и между
    /// строками таблицы одинаковы, разрез неоднозначен; обычно его спасают отступы между операциями.
    public static func rows(
        _ lines: [TextLine],
        boundaries: [CGFloat],
        isAnchor: ([String]) -> Bool
    ) -> [[String]] {
        let ordered = lines
        let cells = ordered.map { self.cells(of: $0, boundaries: boundaries) }
        let anchors = cells.indices.filter { isAnchor(cells[$0]) }
        guard let first = anchors.first, let last = anchors.last else { return [] }

        // Для каждой строки текста — индекс якоря, к которому она относится.
        var owner = Array(repeating: 0, count: ordered.count)
        for index in 0...first { owner[index] = first }
        for index in last..<ordered.count { owner[index] = last }
        for (upper, lower) in zip(anchors, anchors.dropFirst()) {
            var split = upper + 1
            var widest: CGFloat = -.infinity
            for index in (upper + 1)...lower {
                let previous = ordered[index - 1].frame
                let current = ordered[index].frame
                // Новая страница: координаты начались сверху.
                let gap = current.minY < previous.minY ? .infinity : current.minY - previous.maxY
                if gap > widest + 0.5 {
                    widest = gap
                    split = index
                } else if gap >= widest - 0.5 {
                    split = index // почти равный просвет: берём нижний (ячейки, выровненные по верху)
                }
            }
            for index in upper..<split { owner[index] = upper }
            for index in split...lower { owner[index] = lower }
        }

        return anchors.map { anchor in
            var row = Array(repeating: [String](), count: boundaries.count + 1)
            for index in ordered.indices where owner[index] == anchor {
                for (column, text) in cells[index].enumerated() where !text.isEmpty {
                    row[column].append(text)
                }
            }
            return row.map { $0.joined(separator: " ") }
        }
    }
}
