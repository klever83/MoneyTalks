import DesignSystem
import Foundation
import Testing

@Suite("Ввод суммы")
struct AmountInputTests {
    @Test("Запятая, точка и пробелы между разрядами")
    func parsesPositive() {
        #expect(AmountInput.parse("12") == 12)
        #expect(AmountInput.parse("12,5") == Decimal(string: "12.5"))
        #expect(AmountInput.parse("1 250.40") == Decimal(string: "1250.40"))
        #expect(AmountInput.parse(",5") == Decimal(string: "0.5"))
        #expect(AmountInput.parse("1.234") == nil)
        #expect(AmountInput.parse("") == nil)
    }

    @Test("Минус только там, где он разрешён")
    func parsesNegative() {
        #expect(AmountInput.parse("-12,5") == nil)
        #expect(AmountInput.parse("-12,5", allowsNegative: true) == Decimal(string: "-12.5"))
        #expect(AmountInput.parse("\u{2212}1 000", allowsNegative: true) == -1_000)
        #expect(AmountInput.parse("-", allowsNegative: true) == nil)
        #expect(AmountInput.parse("--1", allowsNegative: true) == nil)
    }

    @Test("Текст для поля")
    func text() {
        #expect(AmountInput.text(for: Decimal(string: "-12.5")!) == "12.5")
        #expect(AmountInput.signedText(for: Decimal(string: "-12.5")!) == "-12.5")
    }
}
