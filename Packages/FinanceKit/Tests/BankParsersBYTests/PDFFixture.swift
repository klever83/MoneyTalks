import CoreGraphics
import CoreText
import Foundation

/// Обезличенная выписка, нарисованная в PDF прямо в тесте: та же разметка, что у банка,
/// но выдуманные номера, имена и суммы. Реальные выписки в репозиторий не попадают.
struct PDFFixture {
    enum Alignment { case left, right }

    struct Item {
        var text: String
        var x: CGFloat
        var y: CGFloat
        var alignment: Alignment = .left
    }

    var pageSize = CGSize(width: 842, height: 595)
    var fontSize: CGFloat = 8
    var pages: [[Item]] = [[]]

    /// Текст в точке: `x` — левый край (или правый при `.right`), `y` — верх строки от верха страницы.
    mutating func text(_ text: String, x: CGFloat, y: CGFloat, _ alignment: Alignment = .left) {
        pages[pages.count - 1].append(Item(text: text, x: x, y: y, alignment: alignment))
    }

    mutating func newPage() {
        pages.append([])
    }

    func data() -> Data {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { return Data() }
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        for page in pages {
            context.beginPDFPage(nil)
            for item in page {
                let string = NSAttributedString(
                    string: item.text,
                    attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
                )
                let line = CTLineCreateWithAttributedString(string)
                let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                let x = item.alignment == .right ? item.x - width : item.x
                context.textPosition = CGPoint(x: x, y: pageSize.height - item.y - fontSize)
                CTLineDraw(line, context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
}
