import CoreGraphics
import Foundation
import PDFKit

/// Читает PDF-выписку в `TextLayout`: берёт каждый символ страницы с его положением
/// и собирает строки по координатам. Порядок текста внутри PDF не важен.
public enum PDFStatementReader {
    public enum Failure: Error, Equatable, Sendable {
        /// Файл не открывается как PDF.
        case unreadable
        /// PDF защищён паролем, а пароль не передан или не подошёл.
        case locked
        /// В PDF нет текстового слоя: скан или картинка.
        case noText
        /// Страница повёрнута (`/Rotate`): такие выписки пока не поддерживаются.
        case rotatedPage
    }

    /// Тяжёлая операция: несколько вызовов PDFKit на каждый символ, для выписки на десяток страниц
    /// это заметное время. Не вызывайте на главном потоке, импорт должен запускать её в фоне.
    public static func layout(from data: Data, password: String? = nil) throws(Failure) -> TextLayout {
        guard let document = PDFDocument(data: data) else { throw .unreadable }
        if document.isLocked {
            guard let password, document.unlock(withPassword: password) else { throw .locked }
        }
        var pages: [TextPage] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            guard page.rotation == 0 else { throw .rotatedPage }
            pages.append(textPage(page))
        }
        guard pages.contains(where: { !$0.lines.isEmpty }) else {
            throw .noText
        }
        return TextLayout(pages: pages)
    }

    public static func document(from data: Data, fileName: String, password: String? = nil) throws(Failure) -> StatementDocument {
        StatementDocument(fileName: fileName, format: .pdf, content: .layout(try layout(from: data, password: password)))
    }

    /// PDFKit отдаёт положение символа двумя способами, и оба неточные:
    /// - `selection(for: NSRange)` даёт верный символ, верную горизонталь и высоту строки,
    ///   но у символов многострочной ячейки рамка иногда охватывает всю ячейку;
    /// - `characterBounds(at:)` даёт рамку по «чернилам» символа, но у части генераторов PDF
    ///   (например, iText) её индексы сдвинуты относительно текста страницы.
    /// Поэтому берём рамку выделения, а «высокие» рамки уточняем в `placeTallWords`.
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
            characters.append(Glyph(character, frame: box))
        }

        guard let lineHeight = mostCommonHeight(characters.map(\.frame)) else {
            return TextPage(size: bounds.size, lines: [])
        }
        let hasTallBoxes = characters.contains { $0.frame.height > lineHeight * tallFactor }
        // Точные рамки нужны только там, где есть «высокие» рамки: это лишний проход по PDFKit.
        let exact = hasTallBoxes ? (0..<count).map { flip(page.characterBounds(at: $0)) } : []
        let placed = placeTallWords(characters, exact: exact, lineHeight: lineHeight)
        return TextPage(
            size: bounds.size,
            lines: TextLayoutBuilder.lines(from: placed.glyphs, lineTolerance: 0.25),
            uncertainWords: placed.unmatchedWords
        )
    }

    /// Рамка выше `lineHeight × tallFactor` считается охватывающей несколько строк.
    static let tallFactor: CGFloat = 1.3

    /// Уточняет вертикаль символов с «высокими» рамками выделения.
    ///
    /// - Повторы (тот же символ в той же рамке подряд, так iText дублирует конец строки) отбрасываются.
    /// - Символы группируются в слова по порядку текста: одинаковая рамка по вертикали и соседство по горизонтали.
    /// - Каждому символу по порядку ищется точная рамка с той же горизонталью внутри рамки выделения;
    ///   курсор идёт только вперёд, поэтому символы соседних ячеек с той же горизонталью не путаются.
    /// - «Высокое» слово ставится на строку по медиане центров точных рамок его символов.
    ///   Если точных рамок не нашлось, слово ставится на первую строку своей рамки и попадает в
    ///   `unmatchedWords`: так оно не создаст «фантомную» строку между строками ячейки.
    static func placeTallWords(
        _ characters: [Glyph],
        exact: [CGRect],
        lineHeight: CGFloat
    ) -> (glyphs: [Glyph], unmatchedWords: Int) {
        var unique: [Glyph] = []
        for glyph in characters {
            if let last = unique.last, last.character == glyph.character, last.frame.isAlmostEqual(to: glyph.frame) {
                continue
            }
            unique.append(glyph)
        }
        guard !unique.isEmpty else { return ([], 0) }

        var runs: [Range<Int>] = []
        var start = 0
        for index in unique.indices.dropFirst() {
            let previous = unique[index - 1].frame
            let current = unique[index].frame
            let sameRun = abs(previous.minY - current.minY) < 0.5 && abs(previous.height - current.height) < 0.5
                && current.minX >= previous.minX && current.minX - previous.maxX < lineHeight * 0.3
            if !sameRun {
                runs.append(start..<index)
                start = index
            }
        }
        runs.append(start..<unique.count)

        var cursor = 0
        var exactCenter: [CGFloat?] = Array(repeating: nil, count: unique.count)
        if !exact.isEmpty {
            for index in unique.indices {
                if let match = matchExact(for: unique[index].frame, in: exact, from: cursor) {
                    cursor = match + 1
                    exactCenter[index] = exact[match].midY
                }
            }
        }

        var glyphs = unique
        var unmatched = 0
        for run in runs where unique[run.lowerBound].frame.height > lineHeight * tallFactor {
            let center: CGFloat
            if let median = TextLayoutBuilder.median(run.compactMap { exactCenter[$0] }) {
                center = median
            } else {
                center = unique[run.lowerBound].frame.minY + lineHeight / 2
                unmatched += 1
            }
            for index in run {
                let box = unique[index].frame
                glyphs[index].frame = CGRect(x: box.minX, y: center - lineHeight / 2, width: box.width, height: lineHeight)
            }
        }
        return (glyphs, unmatched)
    }

    /// Самая частая высота рамки (с точностью до 0,5 pt): высота одной строки текста.
    static func mostCommonHeight(_ rects: [CGRect]) -> CGFloat? {
        var counts: [CGFloat: Int] = [:]
        for rect in rects where rect.height > 1 {
            counts[(rect.height * 2).rounded() / 2, default: 0] += 1
        }
        return counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
    }

    /// Ищет точную рамку символа: начинается там же по горизонтали и лежит внутри рамки выделения.
    private static func matchExact(for box: CGRect, in exact: [CGRect], from cursor: Int) -> Int? {
        (cursor..<min(exact.count, cursor + 256)).first { index in
            let rect = exact[index]
            return !rect.isNull
                && abs(rect.minX - box.minX) <= 1.5
                && rect.midY >= box.minY - 1 && rect.midY <= box.maxY + 1
        }
    }
}

extension CGRect {
    func isAlmostEqual(to other: CGRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(maxX - other.maxX) <= tolerance && abs(maxY - other.maxY) <= tolerance
    }
}
