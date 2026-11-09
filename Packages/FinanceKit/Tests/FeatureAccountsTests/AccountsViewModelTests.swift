import Domain
@testable import FeatureAccounts
import Foundation
import Testing

@Suite("Счета: остатки")
@MainActor
struct AccountsViewModelTests {
    @Test("Итоги по валютам в порядке появления")
    func totals() {
        let totals = AccountsViewModel.totals([
            Money(minorUnits: 1_000, currency: .byn),
            Money(minorUnits: 500, currency: .usd),
            Money(minorUnits: -300, currency: .byn),
        ])
        #expect(totals == [Money(minorUnits: 700, currency: .byn), Money(minorUnits: 500, currency: .usd)])
    }

    @Test("Новый текущий остаток меняет начальный, а не операции")
    func editsBalance() throws {
        // Начальный 100, операций на −30: сейчас 70. Пользователь видит в банке 65,50.
        let account = Account(name: "Карта", kind: .card, currency: .byn, openingBalance: Money(minorUnits: 10_000, currency: .byn))
        let edited = try AccountsViewModel.edited(
            account, name: "Зарплатная", kind: .current,
            currentBalance: Decimal(string: "65.50"), knownBalance: Money(minorUnits: 7_000, currency: .byn)
        )
        #expect(edited.name == "Зарплатная" && edited.kind == .current)
        #expect(edited.openingBalance == Money(minorUnits: 9_550, currency: .byn))
    }

    @Test("Остаток не трогается, если не изменился или ещё не известен")
    func keepsOpeningBalance() throws {
        let account = Account(name: "Карта", kind: .card, currency: .byn, openingBalance: Money(minorUnits: 10_000, currency: .byn))
        let same = try AccountsViewModel.edited(
            account, name: "Карта", kind: .card, currentBalance: 70, knownBalance: Money(minorUnits: 7_000, currency: .byn)
        )
        #expect(same.openingBalance == account.openingBalance)
        let unknown = try AccountsViewModel.edited(
            account, name: "Карта", kind: .card, currentBalance: 50, knownBalance: nil
        )
        #expect(unknown.openingBalance == account.openingBalance)
    }
}
