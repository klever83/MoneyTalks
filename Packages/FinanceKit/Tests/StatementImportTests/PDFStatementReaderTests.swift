import CoreGraphics
import CoreText
import Foundation
import StatementImport
import Testing

@Suite("Чтение PDF")
struct PDFStatementReaderTests {
    /// PDF-страница с текстом в заданных точках (начало координат слева сверху).
    /// Текст пишется в файл в том порядке, в каком передан, как у генераторов, пишущих по колонкам.
    private func makePDF(_ items: [(String, CGFloat, CGFloat)]) throws -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 400, height: 300)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        let font = CTFontCreateWithName("Helvetica" as CFString, 10, nil)
        context.beginPDFPage(nil)
        for (text, x, y) in items {
            let string = NSAttributedString(
                string: text,
                attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
            )
            context.textPosition = CGPoint(x: x, y: box.height - y - 10)
            CTLineDraw(CTLineCreateWithAttributedString(string), context)
        }
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    @Test("Текст, записанный по колонкам, читается построчно")
    func columnOrderedText() throws {
        let pdf = try makePDF([
            ("01.10.2026", 20, 40), ("02.10.2026", 20, 60),
            ("-5.00", 300, 40), ("-12.30", 300, 60),
            ("Кофе", 120, 40), ("Такси", 120, 60),
        ])
        let layout = try PDFStatementReader.layout(from: pdf)
        #expect(layout.lines.map(\.text) == ["01.10.2026 Кофе -5.00", "02.10.2026 Такси -12.30"])

        let boundaries = TableExtractor.columnBoundaries(for: layout.lines)
        let rows = TableExtractor.rows(layout.lines, boundaries: boundaries) { $0[0].hasSuffix("2026") }
        #expect(rows == [["01.10.2026", "Кофе", "-5.00"], ["02.10.2026", "Такси", "-12.30"]])
    }

    @Test("PDF без текста и не-PDF дают понятные ошибки")
    func failures() throws {
        #expect(throws: PDFStatementReader.Failure.noText) {
            try PDFStatementReader.layout(from: try makePDF([]))
        }
        #expect(throws: PDFStatementReader.Failure.unreadable) {
            try PDFStatementReader.layout(from: Data("not a pdf".utf8))
        }
    }

    @Test("Документ выписки получает формат pdf и layout")
    func document() throws {
        let document = try PDFStatementReader.document(from: try makePDF([("Выписка", 20, 20)]), fileName: "a.pdf")
        #expect(document.format == .pdf)
        guard case let .layout(layout) = document.content else {
            Issue.record("ожидался layout")
            return
        }
        #expect(layout.text == "Выписка")
    }
}
