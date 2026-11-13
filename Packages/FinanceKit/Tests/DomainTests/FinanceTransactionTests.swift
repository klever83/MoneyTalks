import Domain
import Foundation
import Testing

@Suite("Операция")
struct FinanceTransactionTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func transaction(daysAgo: Double, pending: Bool) -> FinanceTransaction {
        FinanceTransaction(
            accountID: Account.ID(),
            bookedAt: now.addingTimeInterval(-daysAgo * 86_400),
            amount: Money(minorUnits: -500, currency: .byn),
            merchantRaw: "SHOP",
            source: .imported,
            isPending: pending
        )
    }

    @Test("Холд старше 30 дней считается зависшим, проведённая и свежая операции — нет")
    func staleHold() {
        #expect(transaction(daysAgo: 31, pending: true).isStaleHold(now: now))
        #expect(transaction(daysAgo: 30, pending: true).isStaleHold(now: now))
        #expect(!transaction(daysAgo: 29, pending: true).isStaleHold(now: now))
        #expect(!transaction(daysAgo: 60, pending: false).isStaleHold(now: now))
        var deleted = transaction(daysAgo: 60, pending: true)
        deleted.deletedAt = now
        #expect(!deleted.isStaleHold(now: now))
    }
}
