import CoreGraphics
import StatementImport
import Testing

@Suite("Сборка строк из символов")
struct TextLayoutBuilderTests {
    /// Символы слова подряд, по 5 pt на символ, строка высотой 8 pt.
    private func glyphs(_ text: String, x: CGFloat, y: CGFloat) -> [Glyph] {
        text.enumerated().map { offset, character in
            Glyph(character, frame: CGRect(x: x + CGFloat(offset) * 5, y: y, width: 5, height: 8))
        }
    }

    @Test("Порядок символов в файле не важен: строки и слова собираются по координатам")
    func geometryOnly() {
        // Как в PDF, где текст записан по колонкам: сначала все даты, потом все суммы.
        let input = glyphs("01.10", x: 10, y: 10) + glyphs("02.10", x: 10, y: 30)
            + glyphs("-5.00", x: 100, y: 10) + glyphs("12.30", x: 100, y: 30)
        let lines = TextLayoutBuilder.lines(from: input)
        #expect(lines.map(\.text) == ["01.10 -5.00", "02.10 12.30"])
    }

    @Test("Пробел между словами определяется по зазору")
    func wordGaps() {
        let input = glyphs("Оплата", x: 0, y: 0) + glyphs("услуг", x: 33, y: 0)
        #expect(TextLayoutBuilder.lines(from: input).first?.words.map(\.text) == ["Оплата", "услуг"])
    }

    @Test("Символ, смещённый по вертикали (точка, звёздочка), остаётся в своей строке")
    func inkJitter() {
        var input = glyphs("12", x: 0, y: 0)
        input.append(Glyph(".", frame: CGRect(x: 10, y: 6, width: 2, height: 1)))
        input += glyphs("50", x: 12, y: 0)
        input += glyphs("next", x: 0, y: 12)
        #expect(TextLayoutBuilder.lines(from: input).map(\.text) == ["12.50", "next"])
    }
}

@Suite("Таблица из строк")
struct TableExtractorTests {
    private func line(_ y: CGFloat, _ words: (String, CGFloat)...) -> TextLine {
        TextLine(words: words.map { text, x in
            TextWord(text: text, frame: CGRect(x: x, y: y, width: CGFloat(text.count) * 5, height: 8))
        })
    }

    @Test("Границы колонок по просветам и раскладка слов по колонкам")
    func columns() {
        let lines = [
            line(0, ("01.10.2026", 0), ("Кофе", 80), ("-5.00", 200)),
            line(10, ("02.10.2026", 0), ("Такси", 80), ("домой", 107), ("-12.30", 200)),
        ]
        let boundaries = TableExtractor.columnBoundaries(for: lines)
        #expect(boundaries.count == 2)
        #expect(TableExtractor.cells(of: lines[1], boundaries: boundaries) == ["02.10.2026", "Такси домой", "-12.30"])
    }

    @Test("Ячейки, выровненные по центру: строки над якорем относятся к его операции")
    func centeredCells() {
        // Описание в две строки, дата и сумма по центру между ними.
        let lines = [
            line(0, ("Перевод", 80)),
            line(4, ("01.10.2026", 0), ("-5.00", 200)),
            line(8, ("между", 80), ("счетами", 115)),
            line(20, ("Оплата", 80)),
            line(24, ("02.10.2026", 0), ("-7.00", 200)),
            line(28, ("услуг", 80)),
        ]
        let rows = TableExtractor.rows(lines, boundaries: [60, 180]) { $0[0].hasSuffix("2026") }
        #expect(rows == [
            ["01.10.2026", "Перевод между счетами", "-5.00"],
            ["02.10.2026", "Оплата услуг", "-7.00"],
        ])
    }

    @Test("Ячейки, выровненные по верху: продолжение относится к операции выше")
    func topAlignedCells() {
        let lines = [
            line(0, ("01.10.2026", 0), ("TRANSPORT", 80), ("-1.15", 200)),
            line(10, ("PAYBYCARD.BY", 80)),
            line(20, ("MINSK", 80)),
            line(30, ("02.10.2026", 0), ("SHOP", 80), ("-2.00", 200)),
            line(40, ("MINSK", 80)),
        ]
        let rows = TableExtractor.rows(lines, boundaries: [60, 180]) { $0[0].hasSuffix("2026") }
        #expect(rows == [
            ["01.10.2026", "TRANSPORT PAYBYCARD.BY MINSK", "-1.15"],
            ["02.10.2026", "SHOP MINSK", "-2.00"],
        ])
    }
}
