import Domain
import Foundation
import StatementImport
import Testing

@Suite("План импорта")
struct ImportPlannerTests {
    let bank = BankInfo(id: "by.test", name: "Тестбанк", country: "BY")
    let start = Date(timeIntervalSince1970: 1_790_000_000)

    func row(_ minorUnits: Int64, _ description: String, hours: Double = 0, mcc: Int? = nil) -> ParsedRow {
        ParsedRow(
            bookedAt: start.addingTimeInterval(hours * 3_600),
            amount: Money(minorUnits: minorUnits, currency: .byn),
            description: description,
            mcc: mcc
        )
    }

    var statement: ParsedStatement {
        ParsedStatement(
            accountHint: AccountHint(maskedNumber: "4321", currency: .byn),
            rows: [
                row(-1_250, "Retail BLR MINSK SHOP", mcc: 5411),
                row(-10_000, "ATM BLR MINSK ATM 1", hours: 1),
                row(-50_000, "CH Debit BLR MINSK P2P SDBO", hours: 2),
                row(-300, "Retail BLR MINSK COFFEE", hours: 3),
            ]
        )
    }

    @Test("Счёт находится по банку, валюте и последним цифрам")
    func matchesAccount() {
        let card = Account(name: "Карта", kind: .card, currency: .byn, bankID: "by.test", maskedNumber: "•• 4321")
        let other = Account(name: "Другая", kind: .card, currency: .byn, bankID: "by.test", maskedNumber: "•• 1111")
        let foreign = Account(name: "Чужой банк", kind: .card, currency: .byn, bankID: "by.other", maskedNumber: "•• 4321")
        let hint = AccountHint(maskedNumber: "4321", currency: .byn)
        #expect(ImportPlanner.matchAccount(for: hint, bank: bank, among: [foreign, other, card])?.id == card.id)
        #expect(ImportPlanner.matchAccount(for: AccountHint(maskedNumber: "9999", currency: .byn), bank: bank, among: [card]) == nil)
        // Без цифр подходит единственный счёт банка в этой валюте, а из двух не выбираем.
        #expect(ImportPlanner.matchAccount(for: AccountHint(currency: .byn), bank: bank, among: [card])?.id == card.id)
        #expect(ImportPlanner.matchAccount(for: AccountHint(currency: .byn), bank: bank, among: [card, other]) == nil)
    }

    @Test("Новый счёт по выписке: банк и последние цифры карты")
    func proposesAccount() {
        let account = ImportPlanner.proposedAccount(for: statement, bank: bank)
        #expect(account.name == "Тестбанк •• 4321")
        #expect(account.kind == .card && account.currency == .byn)
        #expect(account.bankID == "by.test" && account.maskedNumber == "•• 4321")
    }

    func plan(
        account: Account, existingAccounts: [Account] = [], saved: [FinanceTransaction] = [],
        fingerprints: Set<String> = [], excluded: Set<UUID> = []
    ) -> ImportPlan {
        ImportPlanner.plan(
            statement: statement, bank: bank, account: account, isNewAccount: true,
            existingFingerprints: fingerprints, existingAccounts: existingAccounts,
            recentTransactions: saved, walletName: "Наличные", excludedLinks: excluded
        )
    }

    @Test("Дубли, снятие наличных и перевод на другой счёт")
    func plansImport() {
        let account = ImportPlanner.proposedAccount(for: statement, bank: bank)
        let usdCard = Account.ID()
        let income = FinanceTransaction(
            accountID: usdCard, bookedAt: start.addingTimeInterval(2 * 3_600),
            amount: Money(minorUnits: 50_000, currency: .byn), merchantRaw: "CH Payment BLR MINSK P2P SDBO", source: .imported
        )
        let duplicate = ImportDeduplicator.fingerprints(for: statement.rows, accountID: account.id)[3]
        let plan = plan(account: account, saved: [income], fingerprints: [duplicate])

        #expect(plan.duplicates == 1)
        #expect(plan.newTransactions.map(\.kind) == [.expense, .transfer, .transfer])
        #expect(plan.walletTransactions.count == 1)
        #expect(plan.newWallets.map(\.kind) == [.cash])
        #expect(plan.walletTransactions.first?.accountID == plan.newWallets.first?.id)
        #expect(plan.updatedTransactions.map(\.id) == [income.id])
        #expect(plan.updatedTransactions.first?.transferPairID == plan.newTransactions[2].transferPairID)
        #expect(Set(plan.links.map(\.kind)) == [.cash, .transfer])
        #expect(plan.accountsToSave.count == 2)
        #expect(plan.transactionsToSave.count == 5)
    }

    @Test("Снятые в превью связи не применяются, а идентификаторы плана стабильны")
    func excludedLinks() {
        let account = ImportPlanner.proposedAccount(for: statement, bank: bank)
        let income = FinanceTransaction(
            accountID: Account.ID(), bookedAt: start.addingTimeInterval(2 * 3_600),
            amount: Money(minorUnits: 50_000, currency: .byn), merchantRaw: "CH Payment BLR MINSK P2P SDBO", source: .imported
        )
        let first = plan(account: account, saved: [income])
        let second = plan(account: account, saved: [income], excluded: Set(first.links.map(\.id)))

        #expect(second.links.map(\.id) == first.links.map(\.id))
        #expect(second.links.allSatisfy { $0.isExcluded })
        #expect(second.newTransactions.map(\.id) == first.newTransactions.map(\.id))
        #expect(second.newTransactions.allSatisfy { $0.kind == .expense && $0.transferPairID == nil })
        #expect(second.walletTransactions.isEmpty && second.newWallets.isEmpty && second.updatedTransactions.isEmpty)
    }

    @Test("Свой кошелёк наличных используется, новый не создаётся")
    func reusesWallet() {
        let account = ImportPlanner.proposedAccount(for: statement, bank: bank)
        let wallet = Account(name: "Кошелёк", kind: .cash, currency: .byn)
        let plan = plan(account: account, existingAccounts: [wallet])
        #expect(plan.newWallets.isEmpty)
        #expect(plan.walletTransactions.first?.accountID == wallet.id)
    }
}
