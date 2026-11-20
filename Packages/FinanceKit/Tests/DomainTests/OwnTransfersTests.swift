import Domain
import Foundation
import Testing

@Suite("Переводы на свой счёт без второй стороны")
struct OwnTransfersTests {
    func transaction(_ text: String, minor: Int64 = -100_000, mcc: Int? = nil) -> FinanceTransaction {
        FinanceTransaction(
            accountID: Account.ID(), bookedAt: .now,
            amount: Money(minorUnits: minor, currency: .byn),
            merchantRaw: text, mcc: mcc, source: .imported
        )
    }

    @Test("Формулировки банков, где счёт прямо назван своим", arguments: [
        "Перевод с продажей валюты по списку ПДПП между счетами клиента",
        "CH Debit BLR MINSK Payment From Client Contract",
        "Перевод через АК в рамках одного ФЛ",
        "Перевод на копилку по механике по расписанию",
        "Перечисление средств электронного кошелька на карту ОАО Белинвестбанк",
        "Перевод между своими счетами",
    ])
    func recognizes(text: String) {
        #expect(OwnTransfers.matches(transaction(text)))
        #expect(OwnTransfers.marked(transaction(text)).kind == .transfer)
    }

    @Test("Переводы людям, покупки и комиссии не трогаются", arguments: [
        "Перевод между счетами физических лиц через АК",
        "CH Debit BLR MINSK P2P SDBO",
        "MOBILE BANK BLR, MINSK",
        "Комиссия за перевод между счетами клиента",
        "Retail BLR MINSK EVROOPT",
    ])
    func ignores(text: String) {
        #expect(!OwnTransfers.matches(transaction(text)))
    }

    @Test("MCC покупки важнее текста, связанный, закреплённый, с категорией и «Это не перевод» не отмечаются")
    func guards() {
        let text = "Перевод между своими счетами"
        #expect(!OwnTransfers.matches(transaction(text, mcc: 5411)))
        #expect(OwnTransfers.matches(transaction(text, mcc: 6012)))
        var paired = transaction(text)
        paired.transferPairID = UUID()
        var locked = transaction(text)
        locked.categoryLocked = true
        var categorized = transaction(text)
        categorized.categoryID = FinanceCategory.systemID(for: "other")
        var hold = transaction(text)
        hold.isPending = true
        var declined = transaction(text)
        declined.transferDeclined = true
        for item in [paired, locked, categorized, hold, declined] {
            #expect(OwnTransfers.marked(item) == item)
        }
        // Поступление со своего счёта тоже не доход.
        #expect(OwnTransfers.marked(transaction(text, minor: 5_000)).kind == .transfer)
    }
}
