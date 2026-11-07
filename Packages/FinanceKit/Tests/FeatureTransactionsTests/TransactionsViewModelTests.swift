import Categorization
import Domain
@testable import FeatureTransactions
import Foundation
import Persistence
import Testing

@MainActor
@Suite("Операции: view model")
struct TransactionsViewModelTests {
    let database: AppDatabase
    let transactions: GRDBTransactionRepository
    let accounts: GRDBAccountRepository
    let rules: GRDBCategoryRuleRepository
    let model: TransactionsViewModel
    let groceries = FinanceCategory.systemID(for: "groceries")
    let gifts = FinanceCategory.systemID(for: "gifts")

    init() throws {
        database = try AppDatabase.inMemory()
        transactions = GRDBTransactionRepository(database: database)
        accounts = GRDBAccountRepository(database: database)
        rules = GRDBCategoryRuleRepository(database: database)
        model = TransactionsViewModel(
            transactions: transactions,
            accounts: accounts,
            categories: GRDBCategoryRepository(database: database),
            categorizer: RuleBasedTransactionCategorizer(repository: rules),
            rules: rules
        )
    }

    /// Ждёт, пока поток `observe*` доставит нужное состояние.
    func waitUntil(_ condition: () -> Bool) async throws {
        var attempts = 0
        while !condition(), attempts < 200 {
            try await Task.sleep(for: .milliseconds(10))
            attempts += 1
        }
        #expect(condition())
    }

    func cardAccount() async throws -> Account {
        let account = Account(name: "Карта", kind: .card, currency: .byn)
        try await accounts.save(account)
        return account
    }

    func imported(_ merchant: String, account: Account, minor: Int64 = -1000, categoryID: FinanceCategory.ID? = nil, locked: Bool = false) -> FinanceTransaction {
        FinanceTransaction(
            accountID: account.id, bookedAt: .now,
            amount: Money(minorUnits: minor, currency: .byn),
            merchantRaw: merchant, categoryID: categoryID, categoryLocked: locked, source: .imported
        )
    }

    @Test("Потоки observe доставляют счета, категории и операции, в том числе после изменений")
    func observeStreams() async throws {
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        try await waitUntil { !model.categories.isEmpty }

        let account = try await cardAccount()
        try await waitUntil { model.accounts.map(\.id) == [account.id] }

        try await transactions.save([imported("EVROOPT 12 MINSK", account: account)])
        try await waitUntil { model.transactions.count == 1 }
    }

    @Test("Ручной ввод: знак суммы, закреплённая категория, подсказка по правилам")
    func addManual() async throws {
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        let account = try await cardAccount()
        try await waitUntil { !model.accounts.isEmpty }

        await model.addManual(ManualTransactionDraft(
            accountID: account.id, isExpense: true, amount: 12.5, title: "Подарок",
            categoryID: gifts, date: .now, note: ""
        ))
        await model.addManual(ManualTransactionDraft(
            accountID: account.id, isExpense: true, amount: -3, title: "Евроопт",
            categoryID: nil, date: .now, note: ""
        ))
        await model.addManual(ManualTransactionDraft(
            accountID: account.id, isExpense: false, amount: 100, title: "Долг вернули",
            categoryID: nil, date: .now, note: ""
        ))

        let saved = try await transactions.transactions(TransactionQuery())
        let gift = try #require(saved.first { $0.merchantRaw == "Подарок" })
        #expect(gift.amount.minorUnits == -1250)
        #expect(gift.kind == .expense)
        #expect(gift.categoryID == gifts && gift.categoryLocked)

        let grocery = try #require(saved.first { $0.merchantRaw == "Евроопт" })
        #expect(grocery.amount.minorUnits == -300)
        #expect(grocery.categoryID == groceries && !grocery.categoryLocked)

        let income = try #require(saved.first { $0.merchantRaw == "Долг вернули" })
        #expect(income.amount.minorUnits == 10_000)
        #expect(income.kind == .income)
        #expect(income.categoryID == nil)
    }

    @Test("Смена категории закрепляет её и предлагает «всегда так» с прошлыми операциями мерчанта")
    func changeCategoryOffersAlways() async throws {
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        let account = try await cardAccount()
        let current = imported("EVROOPT 12 MINSK BY", account: account, categoryID: groceries)
        let pastAuto = imported("EVROOPT 45 GRODNO", account: account, categoryID: groceries)
        let pastLocked = imported("EVROOPT 7", account: account, categoryID: groceries, locked: true)
        let other = imported("GIPPO 3", account: account, categoryID: groceries)
        try await transactions.save([current, pastAuto, pastLocked, other])
        try await waitUntil { model.transactions.count == 4 }

        var edited = current
        edited.categoryID = gifts
        let offer = try #require(await model.save(edited, original: current))
        #expect(offer.past.map(\.id) == [pastAuto.id])
        #expect(offer.rule.conditions == [.merchantKey("evroopt")])

        let afterSave = try await transactions.transactions(TransactionQuery())
        #expect(afterSave.first { $0.id == current.id }?.categoryLocked == true)

        await model.acceptAlways(offer, applyToPast: true)
        let all = try await transactions.transactions(TransactionQuery())
        #expect(all.first { $0.id == pastAuto.id }?.categoryID == gifts)
        #expect(all.first { $0.id == pastAuto.id }?.categoryLocked == false)
        #expect(all.first { $0.id == pastLocked.id }?.categoryID == groceries)
        #expect(all.first { $0.id == other.id }?.categoryID == groceries)
        #expect(try await rules.rules().map(\.categoryID) == [gifts])

        // Новая операция мерчанта получает категорию по правилу пользователя.
        let categorizer = RuleBasedTransactionCategorizer(repository: rules)
        let next = try await categorizer.categorize([imported("EVROOPT 99 BREST", account: account)])
        #expect(next.first?.categoryID == gifts)
    }

    @Test("Повторное «всегда так» для того же мерчанта обновляет правило, а не дублирует")
    func alwaysRuleIsUpdated() async throws {
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        let account = try await cardAccount()
        let transaction = imported("EVROOPT 12", account: account)
        try await transactions.save([transaction])
        try await waitUntil { model.transactions.count == 1 }

        var first = transaction
        first.categoryID = gifts
        await model.acceptAlways(try #require(await model.save(first, original: transaction)), applyToPast: false)
        let saved = try #require(try await transactions.transactions(TransactionQuery()).first)
        var second = saved
        second.categoryID = groceries
        await model.acceptAlways(try #require(await model.save(second, original: saved)), applyToPast: false)

        #expect(try await rules.rules().map(\.categoryID) == [groceries])
    }

    @Test("Правка без смены категории не предлагает правило; смена знака меняет тип")
    func plainEdit() async throws {
        let account = try await cardAccount()
        let transaction = imported("EVROOPT 12", account: account, categoryID: groceries)
        try await transactions.save([transaction])

        var edited = transaction
        edited.amount = Money(minorUnits: 1000, currency: .byn)
        edited.note = "возврат"
        #expect(await model.save(edited, original: transaction) == nil)
        let saved = try #require(try await transactions.transactions(TransactionQuery()).first)
        #expect(saved.kind == .income)
        #expect(saved.note == "возврат")
        #expect(!saved.categoryLocked)
    }
}
