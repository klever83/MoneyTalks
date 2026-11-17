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

    @Test("Группы по мерчанту и знаку суммы, крупные сверху, операции без мерчанта по одной в конце")
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
            .merchant(key: "kofemaniya", isExpense: true),
            .merchant(key: "orion kholl", isExpense: true),
            .merchant(key: "kofemaniya", isExpense: false),
            .single(items[6].id),
            .single(items[5].id),
            .single(items[4].id),
        ])
        let coffee = groups[0]
        #expect(coffee.transactions.map(\.id) == [items[1].id, items[0].id])
        #expect(coffee.title == items[1].merchantNormalized)
        #expect(coffee.totals == [Money(minorUnits: -2000, currency: .byn)])
        #expect(coffee.canCreateRule)
        #expect(!groups[3].canCreateRule)
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

        let assignment = UncategorizedReview.assign(group, to: cafes, always: true, rules: [], transactions: all)

        let rule = try #require(assignment.rule)
        #expect(rule.conditions == [.merchantKey("kofemaniya")])
        #expect(rule.origin == .user)
        #expect(Set(assignment.updated.map(\.id)) == [first.id, second.id, refund.id])
        #expect(assignment.updated.allSatisfy { $0.categoryID == cafes && !$0.categoryLocked })
    }

    @Test("Без «всегда так» категория закрепляется только за операциями группы")
    func assignOnce() throws {
        let first = transaction("KOFEMANIYA 12 BLR, MINSK")
        let refund = transaction("KOFEMANIYA 12 BLR, MINSK", minor: 500)
        let all = [first, refund]
        let group = try #require(UncategorizedReview.groups(all).first)

        let assignment = UncategorizedReview.assign(group, to: cafes, always: false, rules: [], transactions: all)

        #expect(assignment.rule == nil)
        #expect(assignment.updated.map(\.id) == [first.id])
        #expect(assignment.updated.allSatisfy { $0.categoryID == cafes && $0.categoryLocked })
    }

    @Test("Операция без мерчанта не даёт правила, даже если просили")
    func singleNeverMakesRule() throws {
        let payment = transaction("MOBILE BANK BLR, MINSK")
        let group = try #require(UncategorizedReview.groups([payment]).first)

        let assignment = UncategorizedReview.assign(group, to: cafes, always: true, rules: [], transactions: [payment])

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
