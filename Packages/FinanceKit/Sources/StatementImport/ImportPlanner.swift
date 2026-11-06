import Domain
import Foundation

/// Связь, найденная при импорте: перевод между своими счетами или снятие наличных.
/// В превью её можно снять, тогда обе операции останутся доходом и расходом.
public struct ImportLink: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable { case transfer, cash }

    /// Идентификатор пары (`transferPairID`): одинаковый при повторном планировании.
    public var id: UUID
    public var kind: Kind
    public var outgoing: FinanceTransaction
    public var incoming: FinanceTransaction
    public var isExcluded: Bool
}

/// Что будет записано в базу после подтверждения импорта.
public struct ImportPlan: Sendable {
    public var statement: ParsedStatement
    public var bank: BankInfo
    public var account: Account
    public var isNewAccount: Bool
    public var batchID: UUID
    /// Новые операции выписки (уже с отметками переводов).
    public var newTransactions: [FinanceTransaction]
    /// Вторые стороны снятия наличных в кошельках.
    public var walletTransactions: [FinanceTransaction]
    /// Кошельки «Наличные», которых ещё нет в приложении.
    public var newWallets: [Account]
    /// Уже сохранённые операции других выписок, ставшие стороной перевода.
    public var updatedTransactions: [FinanceTransaction]
    /// Строки, которые уже импортированы раньше.
    public var duplicates: Int
    public var links: [ImportLink]

    public var accountsToSave: [Account] { (isNewAccount ? [account] : []) + newWallets }
    public var transactionsToSave: [FinanceTransaction] { newTransactions + walletTransactions + updatedTransactions }
}

/// Готовит импорт выписки: счёт, дубли, переводы и снятие наличных. Ничего не пишет в базу.
public enum ImportPlanner {
    static let namespace = UUID(uuidString: "3F8B1D2C-7A64-4E59-B0C1-9D2E6F7A8B31")!

    /// Счёт приложения для выписки: тот же банк, валюта и последние цифры карты или счёта.
    /// Если цифр в выписке нет, подходит единственный счёт банка в этой валюте.
    public static func matchAccount(for hint: AccountHint, bank: BankInfo, among accounts: [Account]) -> Account? {
        let candidates = accounts.filter { account in
            account.deletedAt == nil
                && account.bankID == bank.id
                && (hint.currency == nil || account.currency == hint.currency)
        }
        if let digits = hint.maskedNumber.map(lastDigits), !digits.isEmpty {
            return candidates.first { $0.maskedNumber.map(lastDigits) == digits }
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    /// Новый счёт по выписке: «Приорбанк •• 4321».
    public static func proposedAccount(for statement: ParsedStatement, bank: BankInfo, now: Date = .now) -> Account {
        let digits = statement.accountHint.maskedNumber.map(lastDigits).flatMap { $0.isEmpty ? nil : $0 }
        let currency = statement.accountHint.currency ?? statement.rows.first?.amount.currency ?? .byn
        return Account(
            name: digits.map { "\(bank.name) •• \($0)" } ?? "\(bank.name) \(currency.code)",
            kind: digits == nil ? .current : .card,
            currency: currency,
            bankID: bank.id,
            maskedNumber: digits.map { "•• \($0)" },
            createdAt: now,
            updatedAt: now
        )
    }

    /// План импорта.
    /// - Parameters:
    ///   - existingFingerprints: отпечатки уже сохранённых операций выбранного счёта.
    ///   - existingAccounts: все счета приложения (для кошельков наличных).
    ///   - recentTransactions: сохранённые операции всех счетов за период выписки с запасом
    ///     в окно поиска переводов: с ними ищутся пары для новых строк.
    ///   - walletName: имя для нового кошелька наличных (локализованное).
    ///   - excludedLinks: связи, которые пользователь снял в превью.
    public static func plan(
        statement: ParsedStatement,
        bank: BankInfo,
        account: Account,
        isNewAccount: Bool,
        existingFingerprints: Set<String>,
        existingAccounts: [Account],
        recentTransactions: [FinanceTransaction],
        walletName: String,
        excludedLinks: Set<UUID> = [],
        batchID: UUID = UUID(),
        now: Date = .now
    ) -> ImportPlan {
        let split = ImportDeduplicator.split(statement.rows, accountID: account.id, existing: existingFingerprints)
        let imported = split.new.map { row, fingerprint in
            FinanceTransaction(
                // Постоянный идентификатор: превью можно пересчитать, а снятые связи останутся теми же.
                id: FinanceTransaction.ID(UUID(v5: "\(account.id.rawValue.uuidString)|\(fingerprint)", namespace: namespace)),
                accountID: account.id,
                bookedAt: row.bookedAt,
                amount: row.amount,
                originalAmount: row.originalAmount,
                merchantRaw: row.description,
                mcc: row.mcc,
                source: .imported,
                importBatchID: batchID,
                fingerprint: fingerprint,
                createdAt: now,
                updatedAt: now
            )
        }

        // Снятие наличных: один кошелёк на валюту на весь импорт.
        var wallets: [Currency: Account] = [:]
        let cash = CashWithdrawals.pair(imported, wallet: { currency in
            if let wallet = wallets[currency] { return wallet.id }
            let wallet = CashWithdrawals.wallet(for: currency, among: existingAccounts, name: walletName, now: now)
            wallets[currency] = wallet
            return wallet.id
        }, now: now)
        var links: [ImportLink] = []
        var newTransactions = cash.transactions
        var walletTransactions: [FinanceTransaction] = []
        for side in cash.walletTransactions {
            guard let pairID = side.transferPairID,
                  let index = newTransactions.firstIndex(where: { $0.transferPairID == pairID })
            else { continue }
            let source = newTransactions[index]
            let excluded = excludedLinks.contains(pairID)
            links.append(ImportLink(
                id: pairID,
                kind: .cash,
                outgoing: source.amount.isNegative ? source : side,
                incoming: source.amount.isNegative ? side : source,
                isExcluded: excluded
            ))
            if excluded {
                newTransactions[index] = imported[index]
            } else {
                walletTransactions.append(side)
            }
        }
        let usedWallets = Set(walletTransactions.map(\.accountID))
        let existingIDs = Set(existingAccounts.map(\.id))
        let newWallets = wallets.values
            .filter { usedWallets.contains($0.id) && !existingIDs.contains($0.id) }
            .sorted { $0.currency.code < $1.currency.code }

        // Переводы: новые строки между собой и с уже сохранёнными операциями.
        let importedIDs = Set(newTransactions.map(\.id))
        let saved = recentTransactions.filter { !importedIDs.contains($0.id) }
        let pool = newTransactions + saved
        // Пары только с участием новых строк: старые операции между собой этот импорт не трогает.
        let pairs = TransferMatcher.pairs(in: pool)
            .filter { importedIDs.contains($0.outgoing) || importedIDs.contains($0.incoming) }
        let byID = Dictionary(pool.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for pair in pairs {
            guard let outgoing = byID[pair.outgoing], let incoming = byID[pair.incoming] else { continue }
            links.append(ImportLink(
                id: pair.id, kind: .transfer, outgoing: outgoing, incoming: incoming,
                isExcluded: excludedLinks.contains(pair.id)
            ))
        }
        let applied = TransferMatcher.apply(pairs.filter { !excludedLinks.contains($0.id) }, to: pool, now: now)
        newTransactions = Array(applied.prefix(newTransactions.count))
        let updatedTransactions = zip(saved, applied.dropFirst(newTransactions.count))
            .filter { original, updated in original.transferPairID != updated.transferPairID }
            .map(\.1)

        return ImportPlan(
            statement: statement,
            bank: bank,
            account: account,
            isNewAccount: isNewAccount,
            batchID: batchID,
            newTransactions: newTransactions,
            walletTransactions: walletTransactions,
            newWallets: newWallets,
            updatedTransactions: updatedTransactions,
            duplicates: split.duplicates.count,
            links: links.sorted { $0.outgoing.bookedAt > $1.outgoing.bookedAt }
        )
    }

    private static func lastDigits(_ text: String) -> String {
        String(text.filter(\.isNumber).suffix(4))
    }
}
