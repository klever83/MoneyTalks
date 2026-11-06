import CoreGraphics
import Foundation
import PDFKit

/// Читает PDF-выписку в `TextLayout`: берёт каждый символ страницы с его положением
/// и собирает строки по координатам. Порядок текста внутри PDF не важен.
public enum PDFStatementReader {
    public enum Failure: Error, Equatable, Sendable {
        /// Файл не открывается как PDF или защищён паролем.
        case unreadable
        /// В PDF нет текстового слоя: скан или картинка.
        case noText
    }

    public static func layout(from data: Data) throws(Failure) -> TextLayout {
        guard let document = PDFDocument(data: data), !document.isLocked else {
            throw .unreadable
        }
        var pages: [TextPage] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            pages.append(textPage(page))
        }
        guard pages.contains(where: { !$0.lines.isEmpty }) else {
            throw .noText
        }
        return TextLayout(pages: pages)
    }

    public static func document(from data: Data, fileName: String) throws(Failure) -> StatementDocument {
        StatementDocument(fileName: fileName, format: .pdf, content: .layout(try layout(from: data)))
    }

    /// PDFKit отдаёт положение символа двумя способами, и оба неточные:
    /// - `selection(for: NSRange)` даёт верный символ, верную горизонталь и высоту строки,
    ///   но у символов многострочной ячейки рамка иногда охватывает всю ячейку;
    /// - `characterBounds(at:)` даёт рамку по «чернилам» символа, но у части генераторов PDF
    ///   (например, iText) её индексы сдвинуты относительно текста страницы.
    /// Поэтому берём рамку выделения, а если она выше одной строки, вертикаль слова считаем
    /// по медиане точных рамок его символов (точную рамку ищем по той же горизонтали).
    static func textPage(_ page: PDFPage) -> TextPage {
        let bounds = page.bounds(for: .mediaBox)
        // PDF считает y снизу вверх, переворачиваем в привычные экранные координаты.
        func flip(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX - bounds.minX, y: bounds.maxY - rect.maxY, width: rect.width, height: rect.height)
        }

        let count = page.numberOfCharacters
        var characters: [Glyph] = []
        characters.reserveCapacity(count)
        for index in 0..<count {
            guard let selection = page.selection(for: NSRange(location: index, length: 1)),
                  let character = selection.string?.first,
                  !character.isWhitespace
            else { continue }
            let box = flip(selection.bounds(for: page))
            guard !box.isEmpty else { continue }
            // Часть генераторов дублирует последний символ строки: тот же символ в той же рамке.
            if let last = characters.last, last.character == character, last.frame.isAlmostEqual(to: box) { continue }
            characters.append(Glyph(character, frame: box))
        }
        guard let lineHeight = mostCommonHeight(characters.map(\.frame)) else {
            return TextPage(size: bounds.size, lines: [])
        }

        // Слова в порядке текста: соседние символы с одинаковой рамкой по вертикали.
        var runs: [Range<Int>] = []
        var start = 0
        for index in characters.indices.dropFirst() {
            let previous = characters[index - 1].frame
            let current = characters[index].frame
            let sameRun = abs(previous.minY - current.minY) < 0.5 && abs(previous.height - current.height) < 0.5
                && current.minX >= previous.minX && current.minX - previous.maxX < lineHeight * 0.3
            if !sameRun {
                runs.append(start..<index)
                start = index
            }
        }
        runs.append(start..<characters.count)

        // Точные рамки сопоставляем всем символам по порядку, чтобы курсор не «перепрыгивал»
        // на символы соседних ячеек с той же горизонталью.
        let exact = (0..<count).map { flip(page.characterBounds(at: $0)) }
        var cursor = 0
        var exactCenter: [CGFloat?] = Array(repeating: nil, count: characters.count)
        for index in characters.indices {
            if let match = matchExact(for: characters[index].frame, in: exact, from: cursor) {
                cursor = match + 1
                exactCenter[index] = exact[match].midY
            }
        }

        var glyphs = characters
        for run in runs where characters[run.lowerBound].frame.height > lineHeight * 1.3 {
            guard let center = TextLayoutBuilder.median(run.compactMap { exactCenter[$0] }) else { continue }
            for index in run {
                let box = characters[index].frame
                glyphs[index].frame = CGRect(x: box.minX, y: center - lineHeight / 2, width: box.width, height: lineHeight)
            }
        }
        return TextPage(size: bounds.size, lines: TextLayoutBuilder.lines(from: glyphs, lineTolerance: 0.25))
    }

    /// Самая частая высота рамки (с точностью до 0,5 pt): высота одной строки текста.
    private static func mostCommonHeight(_ rects: [CGRect]) -> CGFloat? {
        var counts: [CGFloat: Int] = [:]
        for rect in rects where rect.height > 1 {
            counts[(rect.height * 2).rounded() / 2, default: 0] += 1
        }
        return counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
    }

    /// Ищет точную рамку символа: начинается там же по горизонтали и лежит внутри рамки выделения.
    private static func matchExact(for box: CGRect, in exact: [CGRect], from cursor: Int) -> Int? {
        let candidates = { (range: Range<Int>) in
            range.first { index in
                let rect = exact[index]
                return !rect.isNull
                    && abs(rect.minX - box.minX) <= 1.5
                    && rect.midY >= box.minY - 1 && rect.midY <= box.maxY + 1
            }
        }
        return candidates(cursor..<min(exact.count, cursor + 256))
    }
}

extension CGRect {
    func isAlmostEqual(to other: CGRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(maxX - other.maxX) <= tolerance && abs(maxY - other.maxY) <= tolerance
    }
}
