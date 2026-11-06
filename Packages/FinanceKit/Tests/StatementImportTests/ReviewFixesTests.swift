import CoreGraphics
import CoreText
import Foundation
import PDFKit
@testable import StatementImport
import Testing

@Suite("Многостраничные таблицы и разрез строк")
struct MultiPageTableTests {
    private func line(_ y: CGFloat, _ words: (String, CGFloat)...) -> TextLine {
        TextLine(words: words.map { text, x in
            TextWord(text: text, frame: CGRect(x: x, y: y, width: CGFloat(text.count) * 5, height: 8))
        })
    }

    @Test("Страницы не перемешиваются, шапка и колонтитул каждой страницы отсеиваются")
    func twoPages() {
        let header = { (y: CGFloat) in self.line(y, ("Дата", 0), ("Описание", 80), ("Сумма", 200)) }
        let layout = TextLayout(pages: [
            TextPage(size: CGSize(width: 300, height: 600), lines: [
                header(40),
                line(60, ("01.10.2026", 0), ("Кофе", 80), ("-5.00", 200)),
                // Операция начинается внизу страницы, описание продолжается на следующей.
                line(540, ("02.10.2026", 0), ("Оплата", 80), ("-7.00", 200)),
                line(580, ("Страница", 0), ("1", 50)),
            ]),
            TextPage(size: CGSize(width: 300, height: 600), lines: [
                header(40),
                line(60, ("услуг", 80)),
                line(90, ("03.10.2026", 0), ("Такси", 80), ("-9.00", 200)),
                line(580, ("Страница", 0), ("2", 50)),
            ]),
        ])
        let lines = TableExtractor.tableLines(
            in: layout,
            isHeader: { $0.text.hasPrefix("Дата") },
            isFooter: { $0.text.hasPrefix("Страница") }
        )
        let rows = TableExtractor.rows(lines, boundaries: [60, 180]) { $0[0].hasSuffix("2026") }
        #expect(rows == [
            ["01.10.2026", "Кофе", "-5.00"],
            ["02.10.2026", "Оплата", "-7.00"],
            ["03.10.2026", "услуг Такси", "-9.00"],
        ])
    }

    @Test("Допуск «почти равных» считается от самого широкого просвета и не сползает вниз")
    func widestGapWins() {
        // Просветы между строками: 10, 9.6, 9.2, 8.8 (высота строки 8).
        let lines = [
            line(0, ("01.10.2026", 0), ("A", 80)),
            line(18, ("B", 80)),
            line(35.6, ("C", 80)),
            line(52.8, ("D", 80)),
            line(69.6, ("02.10.2026", 0), ("E", 80)),
        ]
        let rows = TableExtractor.rows(lines, boundaries: [60]) { $0[0].hasSuffix("2026") }
        // 9.6 почти равен 10 (допуск 0.5) — берём нижний из них; 9.2 и 8.8 уже нет.
        #expect(rows == [["01.10.2026", "A B"], ["02.10.2026", "C D E"]])
    }

    @Test("Порог колонок по умолчанию зависит от кегля: пробел крупного шрифта не граница")
    func relativeMinGap() {
        let big = TextLine(words: [
            TextWord(text: "Оплата", frame: CGRect(x: 0, y: 0, width: 60, height: 14)),
            TextWord(text: "услуг", frame: CGRect(x: 64, y: 0, width: 50, height: 14)),
            TextWord(text: "-5.00", frame: CGRect(x: 200, y: 0, width: 40, height: 14)),
        ])
        #expect(TableExtractor.columnBoundaries(for: [big]).count == 1)
    }
}

@Suite("Уточнение «высоких» рамок PDFKit")
struct TallWordsTests {
    /// Ячейка из двух строк по 8 pt: у PDFKit оба слова получили общую рамку высотой 16 pt.
    private func tall(_ text: String, x: CGFloat) -> [Glyph] {
        text.enumerated().map { offset, character in
            Glyph(character, frame: CGRect(x: x + CGFloat(offset) * 5, y: 100, width: 5, height: 16))
        }
    }

    @Test("Слово ставится на свою строку по точным рамкам, даже если их индексы сдвинуты")
    func placesByExactBoxes() {
        // «07.10» на первой строке ячейки, «11:43» на второй, обе с общей высокой рамкой.
        var characters = tall("07.10", x: 10) + tall("11:43", x: 10)
        // iText дублирует последний символ строки.
        characters.insert(characters[4], at: 5)
        // Точные рамки по «чернилам»: сдвинуты на два индекса (лишние рамки в начале).
        let junk = [CGRect(x: 300, y: 10, width: 4, height: 6), CGRect(x: 310, y: 10, width: 4, height: 6)]
        let first = (0..<5).map { CGRect(x: 10 + CGFloat($0) * 5, y: 101, width: 4, height: 6) }
        let second = (0..<5).map { CGRect(x: 10 + CGFloat($0) * 5, y: 109, width: 4, height: 6) }
        let placed = PDFStatementReader.placeTallWords(characters, exact: junk + first + second, lineHeight: 8)

        #expect(placed.unmatchedWords == 0)
        #expect(placed.glyphs.count == 10)
        let lines = TextLayoutBuilder.lines(from: placed.glyphs, lineTolerance: 0.25)
        #expect(lines.map(\.text) == ["07.10", "11:43"])
    }

    @Test("Слово без точных рамок встаёт на первую строку своей рамки и считается неуверенным")
    func unmatchedWord() {
        let placed = PDFStatementReader.placeTallWords(tall("MINSK", x: 10), exact: [], lineHeight: 8)
        #expect(placed.unmatchedWords == 1)
        #expect(placed.glyphs.allSatisfy { $0.frame.minY == 100 && $0.frame.height == 8 })
    }

    @Test("Обычные рамки не трогаются")
    func normalBoxesUntouched() {
        let normal = [Glyph("A", frame: CGRect(x: 0, y: 0, width: 5, height: 8))]
        let placed = PDFStatementReader.placeTallWords(normal, exact: [], lineHeight: 8)
        #expect(placed.glyphs == normal)
        #expect(placed.unmatchedWords == 0)
    }
}

@Suite("PDF: пароль, поворот, сериализация")
struct PDFEdgeCasesTests {
    private func makePDF(password: String? = nil) throws -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 300, height: 200)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        var info: [CFString: Any] = [:]
        if let password {
            info[kCGPDFContextUserPassword] = password
            info[kCGPDFContextOwnerPassword] = password
        }
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary))
        let font = CTFontCreateWithName("Helvetica" as CFString, 10, nil)
        context.beginPDFPage(nil)
        let string = NSAttributedString(string: "01.10.2026 -5.00", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        context.textPosition = CGPoint(x: 20, y: 150)
        CTLineDraw(CTLineCreateWithAttributedString(string), context)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    @Test("Запароленный PDF: отдельная ошибка без пароля, читается с паролем")
    func locked() throws {
        let pdf = try makePDF(password: "1234")
        #expect(throws: PDFStatementReader.Failure.locked) { try PDFStatementReader.layout(from: pdf) }
        #expect(throws: PDFStatementReader.Failure.locked) { try PDFStatementReader.layout(from: pdf, password: "0000") }
        #expect(try PDFStatementReader.layout(from: pdf, password: "1234").text == "01.10.2026 -5.00")
    }

    @Test("Повёрнутая страница даёт явную ошибку, а не перепутанный текст")
    func rotated() throws {
        let document = try #require(PDFDocument(data: try makePDF()))
        document.page(at: 0)?.rotation = 90
        let data = try #require(document.dataRepresentation())
        #expect(throws: PDFStatementReader.Failure.rotatedPage) { try PDFStatementReader.layout(from: data) }
    }

    @Test("TextLayout сохраняется в JSON и читается обратно: так делаются обезличенные фикстуры")
    func codable() throws {
        let layout = try PDFStatementReader.layout(from: try makePDF())
        let decoded = try JSONDecoder().decode(TextLayout.self, from: JSONEncoder().encode(layout))
        #expect(decoded == layout)
    }
}
