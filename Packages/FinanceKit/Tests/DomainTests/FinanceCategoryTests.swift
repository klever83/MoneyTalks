import Domain
import Foundation
import Testing

@Suite("Категории: скрытие")
struct FinanceCategoryTests {
    @Test("Подкатегория скрытого родителя тоже скрыта")
    func hiddenParentHidesChildren() {
        let food = FinanceCategory(name: "Еда", systemImage: "cart", colorHex: "#FF9500", kind: .expense, isHidden: true)
        let cafe = FinanceCategory(name: "Кафе", systemImage: "cup.and.saucer", colorHex: "#FF9500", parentID: food.id, kind: .expense)
        let transport = FinanceCategory(name: "Транспорт", systemImage: "bus", colorHex: "#007AFF", kind: .expense)
        let taxi = FinanceCategory(name: "Такси", systemImage: "car", colorHex: "#007AFF", parentID: transport.id, kind: .expense)
        let all = [food, cafe, transport, taxi]

        #expect(FinanceCategory.hiddenIDs(all) == [food.id, cafe.id])
        #expect(FinanceCategory.visible(all).map(\.id) == [transport.id, taxi.id])
    }
}

@Suite("Счёт: правка остатка")
struct AccountBalanceTests {
    @Test("Начальный остаток подстраивается под введённый текущий")
    func withCurrentBalance() throws {
        let account = Account(name: "Карта", kind: .card, currency: .byn, openingBalance: Money(minorUnits: 1_000, currency: .byn))
        // Операций на −3 000: сейчас −2 000 (кредитка). В банке −2 500.
        let edited = try account.withCurrentBalance(
            Money(minorUnits: -2_500, currency: .byn), current: Money(minorUnits: -2_000, currency: .byn)
        )
        #expect(edited.openingBalance == Money(minorUnits: 500, currency: .byn))
        #expect(throws: MoneyError.self) {
            try account.withCurrentBalance(.zero(.usd), current: .zero(.byn))
        }
    }
}
