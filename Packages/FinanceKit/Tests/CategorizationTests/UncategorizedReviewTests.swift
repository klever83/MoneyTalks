import Categorization
import Domain
import Foundation
import Testing

@Suite("Разбор операций без категории")
struct UncategorizedReviewTests {
    let account = Account.ID()
    let cafes = FinanceCategory.systemID(for: "cafes")

    func transaction(
        _ merchant: String,
        minor: Int64 = -1000,
        daysAgo: Int = 0,
        change: (inout FinanceTransaction) -> Void = { _ in }
    ) -> FinanceTransaction {
        var transaction = FinanceTransaction(
            accountID: account,
            bookedAt: Date(timeIntervalSince1970: 1_800_000_000 - Double(daysAgo) * 86_400),
            amount: Money(minorUnits: minor, currency: .byn),
            merchantRaw: merchant, source: .imported
        )
        change(&transaction)
        return transaction
    }

    @Test("Группы по мерчанту вместе с возвратами, крупные сверху, операции без мерчанта по одной в конце")
    func grouping() {
        let items = [
            transaction("KOFEMANIYA 12 BLR, MINSK", daysAgo: 1),
            transaction("KOFEMANIYA 45 BLR, GOMEL", daysAgo: 0),
            transaction("KOFEMANIYA 12 BLR, MINSK", minor: 500, daysAgo: 2),
            transaction("ORION KhOLL BLR, MINSK", minor: -5000),
            transaction("MOBILE BANK BLR, MINSK", minor: -2000, daysAgo: 3),
            transaction("MOBILE BANK BLR, MINSK", minor: -3000, daysAgo: 1),
            transaction("Перевод с карты на карту", minor: -700),
            transaction("KOFEMANIYA 1 BLR, MINSK") { $0.categoryID = FinanceCategory.systemID(for: "cafes") },
            transaction("KOFEMANIYA 2 BLR, MINSK") { $0.kind = .transfer },
            transaction("KOFEMANIYA 3 BLR, MINSK") { $0.categoryLocked = true },
        ]

        let groups = UncategorizedReview.groups(items)

        #expect(groups.map(\.id) == [
            .merchant("kofemaniya"),
            .merchant("orion kholl"),
            .single(items[6].id),
            .single(items[5].id),
            .single(items[4].id),
        ])
        let coffee = groups[0]
        #expect(coffee.transactions.map(\.id) == [items[1].id, items[0].id, items[2].id])
        #expect(coffee.title == items[1].merchantNormalized)
        #expect(coffee.totals == [Money(minorUnits: -1500, currency: .byn)])
        #expect(coffee.isExpense)
        #expect(coffee.canCreateRule)
        #expect(!groups[2].canCreateRule)
    }

    @Test("«Всегда так»: правило на мерчанта, раскладка всех его операций без категории, без закрепления")
    func assignAlways() throws {
        let first = transaction("KOFEMANIYA 12 BLR, MINSK")
        let second = transaction("KOFEMANIYA 45 BLR, GOMEL")
        let refund = transaction("KOFEMANIYA 12 BLR, MINSK", minor: 500)
        let locked = transaction("KOFEMANIYA 12 BLR, MINSK") { $0.categoryLocked = true }
        let other = transaction("ORION KhOLL BLR, MINSK")
        let all = [first, second, refund, locked, other]
        let group = try #require(UncategorizedReview.groups(all).first)

        let assignment = UncategorizedReview.assign(group, to: cafes, always: true, rules: [])

        let rule = try #require(assignment.rule)
        #expect(rule.conditions == [.merchantKey("kofemaniya")])
        #expect(rule.origin == .user)
        #expect(Set(assignment.updated.map(\.id)) == [first.id, second.id, refund.id])
        #expect(assignment.updated.allSatisfy { $0.categoryID == cafes && !$0.categoryLocked })
    }

    @Test("Без «всегда так» категория закрепляется только за операциями группы")
    func assignOnce() throws {
        let first = transaction("KOFEMANIYA 12 BLR, MINSK")
        let other = transaction("ORION KhOLL BLR, MINSK", minor: -500)
        let group = try #require(UncategorizedReview.groups([first, other]).first)

        let assignment = UncategorizedReview.assign(group, to: cafes, always: false, rules: [])

        #expect(assignment.rule == nil)
        #expect(assignment.updated.map(\.id) == [first.id])
        #expect(assignment.updated.allSatisfy { $0.categoryID == cafes && $0.categoryLocked })
    }

    @Test("Возвраты мерчанта с покупками разбираются категориями расходов и не меняют правило на доходное")
    func refundsOfMerchantWithPurchases() throws {
        let purchase = transaction("KOFEMANIYA 12 BLR, MINSK") { $0.categoryID = FinanceCategory.systemID(for: "cafes") }
        let refunds = [
            transaction("KOFEMANIYA 12 BLR, MINSK", minor: 500),
            transaction("KOFEMANIYA 45 BLR, GOMEL", minor: 700),
        ]
        let group = try #require(UncategorizedReview.groups([purchase] + refunds).first)
        #expect(group.isExpense)

        let assignment = UncategorizedReview.assign(group, to: cafes, always: true, rules: [])
        #expect(assignment.rule?.conditions == [.merchantKey("kofemaniya")])
        #expect(Set(assignment.updated.map(\.id)) == Set(refunds.map(\.id)))
    }

    @Test("Мерчант только с поступлениями: категории доходов, правило только для поступлений")
    func incomeOnlyMerchant() throws {
        let salary = FinanceCategory.systemID(for: "salary")
        let income = transaction("OOO ROMASHKA", minor: 100_000)
        let group = try #require(UncategorizedReview.groups([income]).first)
        #expect(!group.isExpense)

        let rule = try #require(UncategorizedReview.assign(group, to: salary, always: true, rules: []).rule)
        #expect(rule.conditions == [.merchantKey("ooo romashka"), .amountSign(.positive)])
        #expect(!rule.matches(transaction("OOO ROMASHKA", minor: -500)))

        // Повторный выбор обновляет то же правило.
        let again = UncategorizedReview.assign(group, to: salary, always: true, rules: [rule]).rule
        #expect(again?.id == rule.id)
    }

    @Test("Операция без мерчанта не даёт правила, даже если просили")
    func singleNeverMakesRule() throws {
        let payment = transaction("MOBILE BANK BLR, MINSK")
        let group = try #require(UncategorizedReview.groups([payment]).first)

        let assignment = UncategorizedReview.assign(group, to: cafes, always: true, rules: [])

        #expect(assignment.rule == nil)
        #expect(assignment.updated.map(\.categoryLocked) == [true])
    }

    @Test("Канал платежа не мерчант: «всегда так» на MOBILE BANK не предлагается")
    func channelIsNotMerchant() {
        #expect(AlwaysRule.merchantKey(for: transaction("MOBILE BANK BLR, MINSK")) == nil)
        #expect(AlwaysRule.merchantKey(for: transaction("INTERNET BANK")) == nil)
        #expect(AlwaysRule.merchantKey(for: transaction("ORION KhOLL BLR, MINSK")) == "orion kholl")
    }
}
