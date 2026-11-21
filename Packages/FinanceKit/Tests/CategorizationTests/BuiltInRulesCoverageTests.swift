import Categorization
import Domain
import Foundation
import Testing

/// Названия в том виде, в каком они приходят в выписках без MCC (Приорбанк): кавычки заменены
/// дефисами, префиксы «I.-SHOP», «RBO», хвост эквайера «BAPB», перенос внутри слова.
@Suite("Встроенные правила: выписки без MCC")
struct BuiltInRulesCoverageTests {
    let categorizer = RuleCategorizer(rules: BuiltInRules.all)

    func key(_ merchant: String, minor: Int64 = -1000, mcc: Int? = nil) -> FinanceCategory.ID? {
        categorizer.suggest(for: FinanceTransaction(
            accountID: Account.ID(), bookedAt: .now,
            amount: Money(minorUnits: minor, currency: .byn),
            merchantRaw: merchant, mcc: mcc, source: .imported
        ))?.categoryID
    }

    @Test("Мерчанты из выписок Приорбанка", arguments: [
        ("YANDEX.EDA BLR, MINSK", "cafes"),
        ("I.-SHOP -WILDBERRIES.BY- BLR, MINSK", "marketplaces"),
        ("OMBSHOP.OZON.BY BLR, MINSK", "marketplaces"),
        ("I.-SHOP-WWW.PASS.R W.BY- BLR, MINSK", "transport"),
        ("ZOLOTOE YABLOKO BLR, MINSK", "beauty"),
        ("FITNES-KLUB PRIME GYM BLR, GOMEL", "sport"),
        ("SHOP N9873 FIX PRICE BLR, GOMEL", "home"),
        ("DNS ELEKTRONIKA BLR, GOMEL", "electronics"),
        ("I.-RES.-WWW.PM.BY- BLR, MINSK", "betting"),
        ("ERIP YANDEX.PLUS PARITET BLR, MINSK", "subscriptions"),
        ("SHOP -SEM PYATNITS- BLR, GOMEL", "groceries"),
        ("SHOP -MARK FORMEL- BLR, GOMEL", "clothes"),
        ("WWW.DODOPIZZA.BY BLR, MINSK", "cafes"),
        ("LABORATORIYA HELIX BLR, GOMEL", "health"),
        ("BAR -7PYATNITS- BLR, GOMEL", "cafes"),
        ("ELEMENTUM BLR, GOMEL", "cafes"),
        ("FLOWERS.BY BLR, MINSK", "gifts"),
        ("FASTEN BLR, MINSK", "taxi"),
        ("CH Debit BLR MINSK P2P_SDBO", "transfers_people"),
        ("Перевод P2P PERSON TO PERSON", "transfers_people"),
        ("Перевод между счетами физических лиц через АК", "transfers_people"),
    ])
    func merchants(merchant: String, expected: String) {
        #expect(key(merchant) == FinanceCategory.systemID(for: expected))
    }

    @Test("Общие слова: тип места по названию", arguments: [
        ("KAFE -ZVEZDA- BLR, GOMEL", "cafes"),
        ("REST.-PIVNAYA- BLR, MINSK", "cafes"),
        ("SUShI-BAR TEST BLR, MINSK", "cafes"),
        ("SUPERMARKET TEST BLR, MINSK", "groceries"),
        ("AZS N20 BAPB BLR, GOMEL", "transport"),
        ("PT CHSUP TEST-DENT BLR, GOMEL", "health"),
        ("STELLA TEST HOTEL", "travel"),
        ("BROW BAR TEST BLR, MINSK", "beauty"),
    ])
    func keywords(merchant: String, expected: String) {
        #expect(key(merchant) == FinanceCategory.systemID(for: expected))
    }

    @Test("Общее слово слабее MCC: у банков с MCC решает код")
    func mccBeatsKeyword() {
        #expect(key("BAR TEST", mcc: 5411) == FinanceCategory.systemID(for: "groceries"))
    }

    @Test("Общие слова и короткие названия только целиком", arguments: [
        "BARS SHOP", "STUDENT CLUB", "PIZZALAND", "SPARTAK", "OZONE TEST", "SUNFLOWER TEST", "WWW.SPM.BY TEST",
    ])
    func keywordsNeedBoundaries(merchant: String) {
        #expect(key(merchant) == nil)
    }

    @Test("Некарточные операции Приорбанка: зарплата, проценты, комиссия")
    func bankOperations() {
        #expect(key("Зачисление по ведомости Зачисление согласно ПП N1 от 01.01.2026.", minor: 100_000)
            == FinanceCategory.systemID(for: "salary"))
        #expect(key("Уплата процентов", minor: 350) == FinanceCategory.systemID(for: "interest"))
        #expect(key("Уплата наращенных процентов", minor: 10) == FinanceCategory.systemID(for: "interest"))
        #expect(key("Оплата услуг банка", minor: -500) == FinanceCategory.systemID(for: "fees"))
        #expect(key("Уплата процентов", minor: -350) == nil)
    }

    @Test("Комиссии, связь через ЕРИП и отмена P2P у Альфы, БСБ и БНБ")
    func smallBankOperations() {
        let fees = FinanceCategory.systemID(for: "fees")
        #expect(key("Оплата комиссии за изменение НП/ПР/ РПР", minor: -690) == fees)
        #expect(key("Оплата единого вознаграждения (ежемесячно) в рамках НП/ПР/РПР ЗА ОКТЯБРЬ 2026", minor: -690) == fees)
        #expect(key("Плата за Р2Р перевод в устройствах банка PEREVOD BSB", minor: -400) == fees)
        #expect(key("Плата за перевод", minor: -100) == fees)
        // Бюро переводов: «оплата за перевод» — не комиссия банка.
        #expect(key("Оплата за перевод документов", minor: -5000) != fees)
        // Кэшбэк — не комиссия.
        #expect(key("Комиссионное вознаграждение (money-back)", minor: 1047) != fees)
        #expect(key("Списание со счета BNB-BANK ERIP (MOBIL'NAYA SVYAZ')", minor: -2900)
            == FinanceCategory.systemID(for: "telecom"))
        let people = FinanceCategory.systemID(for: "transfers_people")
        #expect(key("Отмена списания P2P PEREVOD BSB", minor: 9000) == people)
        #expect(key("Списание P2P в устройствах Банка PEREVOD BSB", minor: -9000) == people)
    }
}

@Suite("Раскладка сохранённых операций")
struct CategoryBackfillTests {
    final class Store: TransactionRepository, @unchecked Sendable {
        var stored: [FinanceTransaction]
        init(_ transactions: [FinanceTransaction]) { stored = transactions }
        func observeTransactions(_ query: TransactionQuery) -> AsyncThrowingStream<[FinanceTransaction], any Error> {
            AsyncThrowingStream { $0.finish() }
        }
        func transactions(_ query: TransactionQuery) async throws -> [FinanceTransaction] { stored }
        func save(_ transactions: [FinanceTransaction]) async throws {
            for transaction in transactions {
                if let index = stored.firstIndex(where: { $0.id == transaction.id }) { stored[index] = transaction }
            }
        }
        func delete(_ id: FinanceTransaction.ID) async throws {}
        func fillCategories(_ categories: [FinanceTransaction.ID: FinanceCategory.ID]) async throws -> Int {
            var count = 0
            for (id, categoryID) in categories {
                guard let index = stored.firstIndex(where: { $0.id == id }),
                      UncategorizedReview.isPending(stored[index]) else { continue }
                stored[index].categoryID = categoryID
                count += 1
            }
            return count
        }
        func markTransfers(_ ids: [FinanceTransaction.ID]) async throws -> Int {
            var count = 0
            for id in ids {
                guard let index = stored.firstIndex(where: { $0.id == id }),
                      UncategorizedReview.isPending(stored[index]), stored[index].transferPairID == nil,
                      !stored[index].transferDeclined else { continue }
                stored[index].kind = .transfer
                count += 1
            }
            return count
        }
        func fingerprints(accountID: Account.ID) async throws -> Set<String> { [] }
        func earliestBookedAt(accountID: Account.ID) async throws -> Date? { nil }
    }

    struct NoRules: CategoryRuleRepository {
        func rules() async throws -> [CategoryRule] { [] }
        func save(_ rule: CategoryRule) async throws {}
        func delete(_ id: CategoryRule.ID) async throws {}
    }

    func transaction(_ merchant: String, change: (inout FinanceTransaction) -> Void = { _ in }) -> FinanceTransaction {
        var transaction = FinanceTransaction(
            accountID: Account.ID(), bookedAt: .now,
            amount: Money(minorUnits: -1000, currency: .byn),
            merchantRaw: merchant, source: .imported
        )
        change(&transaction)
        return transaction
    }

    @Test("Операции без категории получают её, выбор пользователя и переводы не трогаются")
    func backfill() async throws {
        let cafe = transaction("YANDEX.EDA BLR, MINSK")
        let unknown = transaction("SOMETHING UNKNOWN")
        let locked = transaction("YANDEX.EDA BLR, MINSK") { $0.categoryLocked = true }
        let transfer = transaction("YANDEX.EDA BLR, MINSK") { $0.kind = .transfer }
        let store = Store([cafe, unknown, locked, transfer])

        let count = try await CategoryBackfill.run(
            transactions: store,
            categorizer: RuleBasedTransactionCategorizer(repository: NoRules())
        )

        #expect(count == 1)
        let byID = Dictionary(uniqueKeysWithValues: store.stored.map { ($0.id, $0) })
        #expect(byID[cafe.id]?.categoryID == FinanceCategory.systemID(for: "cafes"))
        #expect(byID[unknown.id]?.categoryID == nil)
        #expect(byID[locked.id]?.categoryID == nil)
        #expect(byID[transfer.id]?.categoryID == nil)
    }

    @Test("Перевод на свой счёт без второй стороны становится переводом, а не расходом без категории")
    func backfillOwnTransfers() async throws {
        let currency = transaction("Перевод с продажей валюты по списку ПДПП между счетами клиента")
        let piggy = transaction("Перевод на копилку по механике по расписанию")
        let p2p = transaction("CH Debit BLR MINSK P2P SDBO")
        let lockedOwn = transaction("Перевод через АК в рамках одного ФЛ") { $0.categoryLocked = true }
        let store = Store([currency, piggy, p2p, lockedOwn])

        let count = try await CategoryBackfill.run(
            transactions: store,
            categorizer: RuleBasedTransactionCategorizer(repository: NoRules())
        )

        #expect(count == 3)
        let byID = Dictionary(uniqueKeysWithValues: store.stored.map { ($0.id, $0) })
        #expect(byID[currency.id]?.kind == .transfer)
        #expect(byID[piggy.id]?.kind == .transfer)
        #expect(byID[currency.id]?.transferPairID == nil)
        // Перевод человеку может быть чужим счётом: расход «Переводы людям». Выбор пользователя не трогается.
        #expect(byID[p2p.id]?.kind == .expense)
        #expect(byID[p2p.id]?.categoryID == FinanceCategory.systemID(for: "transfers_people"))
        #expect(byID[lockedOwn.id]?.kind == .expense)
    }

    @Test("«Это не перевод» переживает следующую раскладку: операция остаётся расходом")
    func declinedTransferStaysExpense() async throws {
        let own = transaction("Перевод через АК в рамках одного ФЛ")
        let store = Store([own])
        let categorizer = RuleBasedTransactionCategorizer(repository: NoRules())

        #expect(try await CategoryBackfill.run(transactions: store, categorizer: categorizer) == 1)
        let marked = try #require(store.stored.first)
        #expect(marked.kind == .transfer)

        let restored = try #require(QuickReview.undoTransfer(marked))
        try await store.save([restored])
        // Новая версия правил или восстановление копии запускают раскладку снова.
        #expect(try await CategoryBackfill.run(transactions: store, categorizer: categorizer) == 0)
        let after = try #require(store.stored.first)
        #expect(after.kind == .expense)
        #expect(after.transferDeclined)
        #expect(UncategorizedReview.isPending(after))
    }
}
