import CoreGraphics
import Foundation

/// Текст страницы с координатами: слова, собранные в строки по положению на странице,
/// а не по порядку, в котором их записал генератор PDF.
///
/// Система координат: начало в левом верхнем углу страницы, `y` растёт вниз.
public struct TextLayout: Hashable, Codable, Sendable {
    public var pages: [TextPage]

    public init(pages: [TextPage]) {
        self.pages = pages
    }

    /// Весь текст построчно, страницы разделены пустой строкой.
    public var text: String {
        pages.map { $0.lines.map(\.text).joined(separator: "\n") }.joined(separator: "\n\n")
    }

    /// Все строки документа подряд, со всех страниц. Координаты у каждой страницы свои.
    public var lines: [TextLine] {
        pages.flatMap(\.lines)
    }

    public var uncertainWords: Int {
        pages.reduce(0) { $0 + $1.uncertainWords }
    }
}

public struct TextPage: Hashable, Codable, Sendable {
    public var size: CGSize
    public var lines: [TextLine]
    /// Слова, положение которых по вертикали пришлось угадать (PDFKit не дал точных рамок).
    /// Если не ноль, парсеру стоит предупредить пользователя: описания могли перепутаться.
    public var uncertainWords: Int

    public init(size: CGSize, lines: [TextLine], uncertainWords: Int = 0) {
        self.size = size
        self.lines = lines
        self.uncertainWords = uncertainWords
    }
}

/// Строка: слова с общей вертикалью, слева направо.
public struct TextLine: Hashable, Codable, Sendable {
    public var words: [TextWord]

    public init(words: [TextWord]) {
        self.words = words
    }

    public var text: String {
        words.map(\.text).joined(separator: " ")
    }

    public var frame: CGRect {
        words.map(\.frame).reduce(CGRect.null) { $0.union($1) }
    }
}

/// Слово: символы без пробела между ними.
public struct TextWord: Hashable, Codable, Sendable {
    public var text: String
    public var frame: CGRect

    public init(text: String, frame: CGRect) {
        self.text = text
        self.frame = frame
    }
}

/// Символ с рамкой на странице.
public struct Glyph: Hashable, Sendable {
    public var character: Character
    public var frame: CGRect

    public init(_ character: Character, frame: CGRect) {
        self.character = character
        self.frame = frame
    }
}

/// Собирает символы в слова и строки только по геометрии.
public enum TextLayoutBuilder {
    /// - Parameters:
    ///   - lineTolerance: доля типичной высоты символа; символ с серединой ближе к средней линии строки
    ///     относится к этой строке.
    ///   - wordGap: доля типичной ширины символа; зазор больше неё начинает новое слово.
    public static func lines(
        from glyphs: [Glyph],
        lineTolerance: CGFloat = 0.6,
        wordGap: CGFloat = 0.3
    ) -> [TextLine] {
        let visible = glyphs.filter { !$0.character.isWhitespace && !$0.frame.isNull && $0.frame.width > 0 }
        guard !visible.isEmpty else { return [] }

        // Рамки символов бывают «по чернилам»: у точки высота почти ноль, у «р» рамка ниже строки.
        // Поэтому допуски считаем от типичного символа страницы, а не от каждого символа отдельно.
        let typicalHeight = median(visible.map(\.frame.height).filter { $0 > 1 }) ?? 1
        let typicalWidth = median(visible.map(\.frame.width)) ?? 1

        let byRow = visible.sorted {
            $0.frame.midY != $1.frame.midY ? $0.frame.midY < $1.frame.midY : $0.frame.minX < $1.frame.minX
        }
        var rows: [[Glyph]] = []
        var centers: [CGFloat] = []
        for glyph in byRow {
            if let center = centers.last, abs(glyph.frame.midY - center) <= lineTolerance * typicalHeight {
                rows[rows.count - 1].append(glyph)
                centers[centers.count - 1] = median(rows[rows.count - 1].map(\.frame.midY)) ?? center
            } else {
                rows.append([glyph])
                centers.append(glyph.frame.midY)
            }
        }

        let threshold = wordGap * typicalWidth
        return rows.map { row in
            var words: [TextWord] = []
            var text = ""
            var frame = CGRect.null
            for glyph in row.sorted(by: { $0.frame.minX < $1.frame.minX }) {
                if !text.isEmpty, glyph.frame.minX - frame.maxX > threshold {
                    words.append(TextWord(text: text, frame: frame))
                    text = ""
                    frame = .null
                }
                text.append(glyph.character)
                frame = frame.union(glyph.frame)
            }
            if !text.isEmpty {
                words.append(TextWord(text: text, frame: frame))
            }
            return TextLine(words: words)
        }
    }

    static func median(_ values: [CGFloat]) -> CGFloat? {
        guard !values.isEmpty else { return nil }
        return values.sorted()[values.count / 2]
    }
}

extension TextLine {
    /// Группы слов, разделённые просветом шире `minGap`: в таблицах без рамок это обычно ячейки.
    /// Слова внутри группы склеиваются через пробел, так `1 899.13` остаётся одной суммой.
    public func segments(minGap: CGFloat) -> [String] {
        var segments: [[String]] = []
        var lastMaxX: CGFloat?
        for word in words.sorted(by: { $0.frame.minX < $1.frame.minX }) {
            if let lastMaxX, word.frame.minX - lastMaxX < minGap {
                segments[segments.count - 1].append(word.text)
            } else {
                segments.append([word.text])
            }
            lastMaxX = max(lastMaxX ?? word.frame.maxX, word.frame.maxX)
        }
        return segments.map { $0.joined(separator: " ") }
    }
}
