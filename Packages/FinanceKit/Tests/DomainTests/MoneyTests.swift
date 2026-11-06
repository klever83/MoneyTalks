import Domain
import Foundation
import Testing

@Suite("Money")
struct MoneyTests {
    @Test("Десятичное значение округляется до копеек")
    func roundsToMinorUnits() {
        #expect(Money(Decimal(string: "12.345")!, currency: .byn).minorUnits == 1235)
        #expect(Money(Decimal(string: "-12.345")!, currency: .byn).minorUnits == -1235)
        #expect(Money(Decimal(string: "0.004")!, currency: .usd).minorUnits == 0)
    }

    @Test("Обратное преобразование в Decimal без потерь")
    func decimalValue() {
        #expect(Money(minorUnits: 123456, currency: .byn).decimalValue == Decimal(string: "1234.56"))
    }

    @Test("Сложение разных валют запрещено")
    func addingMismatchedCurrencies() throws {
        let byn = Money(minorUnits: 100, currency: .byn)
        let usd = Money(minorUnits: 100, currency: .usd)
        #expect(throws: MoneyError.currencyMismatch(.byn, .usd)) {
            try byn.adding(usd)
        }
        #expect(try byn.adding(byn).minorUnits == 200)
    }

    @Test("Пересчёт по курсу")
    func conversion() {
        let usd = Money(minorUnits: 10_000, currency: .usd)
        let byn = usd.converted(to: .byn, rate: Decimal(string: "3.2541")!)
        #expect(byn == Money(minorUnits: 32_541, currency: .byn))
        #expect(usd.converted(to: .usd, rate: 5) == usd)
    }

    @Test("Вид операции по знаку суммы")
    func transactionKind() {
        let account = Account(name: "Карта", kind: .card, currency: .byn)
        let expense = FinanceTransaction(
            accountID: account.id, bookedAt: .now,
            amount: Money(minorUnits: -500, currency: .byn), merchantRaw: "Кофе", source: .manual
        )
        let income = FinanceTransaction(
            accountID: account.id, bookedAt: .now,
            amount: Money(minorUnits: 500, currency: .byn), merchantRaw: "Зарплата", source: .manual
        )
        #expect(expense.kind == .expense)
        #expect(income.kind == .income)
    }
}
