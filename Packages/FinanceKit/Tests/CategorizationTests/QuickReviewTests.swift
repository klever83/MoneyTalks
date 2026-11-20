import Categorization
import Domain
import Foundation
import Testing

@Suite("Анкета разбора трат")
struct QuickReviewTests {
    let card = Account.ID()
    let otherBank = Account.ID()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let cafes = FinanceCategory.systemID(for: "cafes")
    let groceries = FinanceCategory.systemID(for: "groceries")
    let taxi = FinanceCategory.systemID(for: "taxi")

    func transaction(
        _ merchant: String,
        minor: Int64 = -1000,
        account: Account.ID? = nil,
        mcc: Int? = nil,
        change: (inout FinanceTransaction) -> Void = { _ in }
    ) -> FinanceTransaction {
        var transaction = FinanceTransaction(
            accountID: account ?? card, bookedAt: now,
            amount: Money(minorUnits: minor, currency: .byn),
            merchantRaw: merchant, mcc: mcc, source: .imported
        )
        change(&transaction)
        return transaction
    }

    func category(_ key: String, kind: FinanceCategory.Kind = .expense) -> FinanceCategory {
        FinanceCategory(id: FinanceCategory.systemID(for: key), name: key, systemImage: "tag", colorHex: "#888888", kind: kind)
    }

    @Test("Очередь: только расходы, крупные по сумме первыми, без отложенных и не длиннее лимита")
    func queue() {
        let items = [
            transaction("FASTEN BLR, MINSK", minor: -300),
            transaction("FASTEN BLR, MINSK", minor: -300),
            transaction("ORION KhOLL BLR, MINSK", minor: -5000),
            transaction("GOSTINNAYA BLR, MINSK", minor: -900),
            transaction("OOO ROMASHKA", minor: 100_000),
        ]
        let groups = UncategorizedReview.groups(items)

        #expect(QuickReview.queue(groups).map(\.title) == [
            items[2].merchantNormalized, items[3].merchantNormalized, items[0].merchantNormalized,
        ])
        let snoozed = QuickReview.queue(groups, snoozedUntil: ["orion kholl": now.addingTimeInterval(60)], now: now)
        #expect(snoozed.map(\.title) == [items[3].merchantNormalized, items[0].merchantNormalized])
        let expired = QuickReview.queue(groups, snoozedUntil: ["orion kholl": now.addingTimeInterval(-60)], now: now)
        #expect(expired.count == 3)
        #expect(QuickReview.queue(groups, limit: 1).count == 1)
    }

    @Test("MOBILE BANK: один вопрос на все платежи, ответы «свои карты» и «одна категория»")
    func channels() throws {
        let items = [
            transaction("MOBILE BANK BLR, MINSK", minor: -2000),
            transaction("MOBILE BANK BLR, MINSK", minor: -3000),
            transaction("MOBILE BANK BLR, MINSK", minor: 4000),
            transaction("ORION KhOLL BLR, MINSK"),
        ]
        let channel = try #require(QuickReview.channelGroups(items).first)
        #expect(QuickReview.channelGroups(items).count == 1)
        #expect(channel.transactions.count == 2)
        #expect(channel.totals == [Money(minorUnits: -5000, currency: .byn)])

        let transfers = QuickReview.markAsTransfers(channel)
        #expect(transfers.allSatisfy { $0.kind == .transfer && $0.categoryID == nil })
        let assigned = QuickReview.assign(channel, to: cafes)
        #expect(assigned.allSatisfy { $0.categoryID == cafes && $0.categoryLocked })
    }

    @Test("Подсказки: тот же мерчант в другом банке, MCC, потом частые категории пользователя")
    func suggestions() throws {
        let pending = transaction("KOFEMANIYA 12 BLR, MINSK")
        let items = [
            pending,
            // Тот же мерчант в выписке другого банка с MCC: такси (4121).
            transaction("KOFEMANIYA 45 GOMEL", account: otherBank, mcc: 4121) { $0.categoryID = FinanceCategory.systemID(for: "taxi") },
            transaction("KOFEMANIYA 46 GOMEL", account: otherBank, mcc: 5814),
            transaction("EVROOPT 1") { $0.categoryID = FinanceCategory.systemID(for: "groceries") },
            transaction("EVROOPT 2") { $0.categoryID = FinanceCategory.systemID(for: "groceries") },
        ]
        let group = try #require(UncategorizedReview.groups(items).first)
        let categories = [category("cafes"), category("groceries"), category("taxi"), category("salary", kind: .income)]

        let ids = QuickReview.suggestions(for: group, transactions: items, categories: categories)

        #expect(ids == [taxi, cafes, groceries])
        #expect(QuickReview.suggestions(for: group, transactions: items, categories: categories, limit: 1) == [taxi])
    }

    @Test("Прогресс: доля расходов с категорией в основной валюте, без переводов и поступлений")
    func progress() throws {
        let items = [
            transaction("EVROOPT", minor: -3000) { $0.categoryID = FinanceCategory.systemID(for: "groceries") },
            transaction("FASTEN", minor: -1000),
            transaction("ПЕРЕВОД", minor: -50_000) { $0.kind = .transfer },
            transaction("ЗАРПЛАТА", minor: 100_000),
        ]
        let progress = try #require(QuickReview.progress(items))
        #expect(progress.currency == .byn)
        #expect(progress.categorizedShare == 0.75)
        #expect(QuickReview.progress([]) == nil)
    }
}
