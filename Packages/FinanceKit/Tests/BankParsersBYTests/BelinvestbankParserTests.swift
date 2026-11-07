import BankParsersBY
import Domain
import Foundation
import StatementImport
import Testing

@Suite("Белинвестбанк: карта и кошелёк Оплати")
struct BelinvestbankParserTests {
    private static var minsk: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Minsk")!
        return calendar
    }

    // MARK: - Карта

    /// Разметка как у мини-выписки по карточке, данные выдуманные. Шапка только на первой странице,
    /// строки от новых к старым, в каждой ячейке до трёх строк через 14 pt.
    static func card(expense: String = "31.15") -> PDFFixture {
        var pdf = PDFFixture()
        pdf.pageSize = CGSize(width: 595, height: 842)
        pdf.fontSize = 6
        pdf.text("Список платежей", x: 252, y: 31)
        pdf.text("Мини-выписка по карточке **** **** **** 1234 за период с 01.11.2026 по 07.11.2026", x: 158, y: 52)
        pdf.text("Доступная сумма: 30.00 Заблокировано: -1.15", x: 31, y: 119)
        pdf.text("Валюта счета: BYN", x: 31, y: 145)

        let header: [(String, CGFloat, CGFloat)] = [
            ("Дата", 31, 165), ("Дата", 70, 165), ("№ Карточки", 111, 165), ("Код", 153, 165), ("Тип операции", 201, 165),
            ("MCC", 263, 165), ("Место", 286, 165), ("Сумма в", 343, 165), ("Сумма и", 385, 165), ("Остаток", 449, 165),
            ("Статус", 493, 165), ("Номер", 536, 165),
            ("операции", 31, 179), ("обработки", 70, 179), ("авторизации", 153, 179), ("проведения", 286, 179),
            ("валюте", 343, 179), ("комиссия в", 385, 179), ("после", 452, 179), ("операции в", 529, 179),
            ("транзакции", 343, 193), ("валюте счета на", 385, 193), ("операции", 446, 193), ("ЕРИП", 537, 193),
            ("дату обработки", 385, 207), ("операции", 385, 221),
        ]
        for (text, x, y) in header { pdf.text(text, x: x, y: y) }

        func row(
            _ y: CGFloat, date: String, time: String, processed: String?, auth: String, mcc: String,
            place: [String], operation: String, account: String, balance: String, status: [String]
        ) {
            pdf.text(date, x: 31, y: y)
            pdf.text(time, x: 31, y: y + 14)
            if let processed { pdf.text(processed, x: 70, y: y) }
            pdf.text("**** 1234", x: 115, y: y)
            pdf.text(auth, x: 153, y: y)
            pdf.text("Покупка", x: 201, y: y)
            pdf.text(mcc, x: 262, y: y)
            for (index, line) in place.enumerated() { pdf.text(line, x: 286, y: y + CGFloat(index) * 14) }
            pdf.text(operation, x: 354, y: y)
            pdf.text(account, x: 390, y: y)
            pdf.text(balance, x: 452, y: y)
            for (index, line) in status.enumerated() { pdf.text(line, x: 487, y: y + CGFloat(index) * 14) }
        }

        row(236, date: "2026-11-06", time: "13:28:23", processed: nil, auth: "111111", mcc: "4111",
            place: ["TRANSPORT", "PAYBYCARD.BY", ">g MINSK BY"], operation: "-1.15 BYN", account: "0.00/0.00",
            balance: "28.85", status: ["ЗАБЛОКИРОВ", "АНО"])
        row(279, date: "2026-11-04", time: "11:56:29", processed: "2026-11-06", auth: "222222", mcc: "5411",
            place: ["SHOP TEST", "g MINSK"], operation: "-10.00 USD", account: "-29.50/0.50 BYN",
            balance: "30.00 BYN", status: ["ПРОВЕДЕНО"])
        pdf.text("Стр. 1", x: 545, y: 809)

        pdf.newPage()
        row(31, date: "2026-11-02", time: "23:52:43", processed: "2026-11-04", auth: "333333", mcc: "4111",
            place: ["TRANSPORT", "PAYBYCARD.BY", "g MINSK"], operation: "-1.15 BYN", account: "-1.15/0.00 BYN",
            balance: "60.00 BYN", status: ["ПРОВЕДЕНО"])
        pdf.text("Приход: 0.00 BYN", x: 31, y: 120)
        pdf.text("ОАО \"Белинвестбанк\"", x: 493, y: 123)
        pdf.text("Расход: \(expense) BYN", x: 31, y: 129)
        pdf.text("BLBBBY2X", x: 508, y: 151)
        pdf.text("Стр. 2", x: 545, y: 809)
        return pdf
    }

    static func parseCard(_ pdf: PDFFixture) throws -> ParsedStatement {
        let document = try PDFStatementReader.document(from: pdf.data(), fileName: "card.pdf")
        return try BelinvestbankParser().parse(document)
    }

    @Test("Карта: проведённые операции с двух страниц, комиссия отдельной строкой")
    func cardRows() throws {
        let rows = try Self.parseCard(Self.card()).rows
        #expect(rows.map(\.amount.minorUnits) == [-2_950, -50, -115])
        #expect(rows.allSatisfy { $0.amount.currency == .byn })
        #expect(rows.map(\.description) == [
            "SHOP TEST g MINSK",
            "Комиссия: SHOP TEST g MINSK",
            "TRANSPORT PAYBYCARD.BY g MINSK",
        ])
        #expect(rows.map(\.mcc) == [5411, nil, 4111])
        #expect(rows[0].originalAmount == Money(minorUnits: -1_000, currency: .usd))
        #expect(rows[2].originalAmount == nil)
        #expect(Set(rows.compactMap(\.bankReference)).count == 3)
        let components = Self.minsk.dateComponents([.year, .month, .day, .hour, .minute, .second], from: rows[0].bookedAt)
        #expect(components == DateComponents(year: 2026, month: 11, day: 4, hour: 11, minute: 56, second: 29))
    }

    @Test("Карта: остатки по цепочке, заблокированные не импортируются")
    func cardBalances() throws {
        let statement = try Self.parseCard(Self.card())
        #expect(statement.accountHint == AccountHint(maskedNumber: "1234", currency: .byn))
        #expect(statement.openingBalance == Money(minorUnits: 6_115, currency: .byn))
        #expect(statement.closingBalance == Money(minorUnits: 3_000, currency: .byn))
        #expect(statement.warnings.map(\.message) == [
            "Заблокированные суммы не импортированы (1): они появятся после проведения. Следующую выписку выгрузите начиная с 07.11.2026",
        ])
        let start = try #require(statement.period?.start)
        #expect(Self.minsk.dateComponents([.month, .day], from: start) == DateComponents(month: 11, day: 1))
    }

    @Test("Карта: если расход не сходится с операциями, парсер предупреждает")
    func cardMismatch() throws {
        let warnings = try Self.parseCard(Self.card(expense: "30.00")).warnings.map(\.message)
        #expect(warnings.contains { $0.hasPrefix("Сумма операций не сходится") })
    }

    // MARK: - Оплати

    /// Разметка как у выписки по электронному кошельку, данные выдуманные.
    /// Тип платежа в узкой колонке перенесён посреди слова, как у банка.
    static func wallet(income: String = "50", expense: String = "18.91") -> PDFFixture {
        var pdf = PDFFixture()
        pdf.pageSize = CGSize(width: 595, height: 842)
        pdf.fontSize = 6
        pdf.text("07.11.2026 00:13", x: 36, y: 41)
        pdf.text("ОАО \"Белинвестбанк\"", x: 36, y: 51)
        pdf.text("Выписка по операциям электронного кошелька BY00BLBB00000000000000000000 ТЕСТОВ ТЕСТ за период с", x: 43, y: 72)
        pdf.text("01.08.2026 по 31.10.2026", x: 254, y: 83)
        pdf.text("Валюта кошелька: BYN", x: 36, y: 104)
        pdf.text("Остаток на начало периода: 3.80 BYN", x: 36, y: 125)

        let header: [(String, CGFloat, CGFloat)] = [
            ("Дата и", 38, 154), ("Id", 83, 154), ("Тип", 126, 154), ("Приход", 159, 154), ("Расход", 190, 154),
            ("Остаток", 220, 154), ("Валюта", 256, 154), ("Детали операции (контрагент)", 293, 154),
            ("время", 38, 161), ("операции", 83, 161), ("платежа", 126, 161), ("после", 220, 161), ("операции", 256, 161),
            ("транзакции", 38, 168), ("операции", 220, 168),
        ]
        for (text, x, y) in header { pdf.text(text, x: x, y: y) }

        func row(_ y: CGFloat, _ date: String, _ time: String, id: String, type: [String], income: String?,
                 expense: String?, balance: String, details: [String]) {
            pdf.text(date, x: 38, y: y)
            pdf.text(time, x: 38, y: y + 7)
            pdf.text(id, x: 83, y: y)
            for (index, line) in type.enumerated() { pdf.text(line, x: 126, y: y + CGFloat(index) * 7) }
            if let income { pdf.text(income, x: 159, y: y) }
            if let expense { pdf.text(expense, x: 190, y: y) }
            pdf.text(balance, x: 220, y: y)
            pdf.text("BYN", x: 256, y: y)
            for (index, line) in details.enumerated() { pdf.text(line, x: 293, y: y + CGFloat(index) * 7) }
        }
        row(179, "11.08.2026", "18:03", id: "600000001", type: ["Оплата", "товаров", "/услуг"], income: nil,
            expense: "1.1", balance: "2.70", details: ["Оплата товаров/услуг TEST TRANSPORT"])
        row(204, "12.08.2026", "20:23", id: "600000002", type: ["Пополне", "ние", "кошельк", "а"], income: "50",
            expense: nil, balance: "52.70", details: ["Пополнение электронного кошелька с текущего счета", "BY00BLBB00000000000000000000, 50 р."])
        row(236, "09.09.2026", "16:24", id: "600000003", type: ["Оплата", "в ЕРИП"], income: nil,
            expense: "12.81", balance: "39.89", details: [])
        row(254, "09.09.2026", "16:30", id: "600000004", type: ["Вывод", "средств"], income: nil,
            expense: "5.0", balance: "34.89",
            details: ["Перечисление средств с электронного кошелька на банковскую карту ОАО", "\"Белинвестбанк\" 000000******1234"])
        pdf.text("Итого", x: 38, y: 272)
        pdf.text(income, x: 159, y: 272)
        pdf.text(expense, x: 190, y: 272)
        pdf.text("BYN", x: 256, y: 272)
        pdf.text("обороты за", x: 38, y: 279)
        pdf.text("Остаток на", x: 38, y: 297)
        pdf.text("34.89", x: 83, y: 297)
        pdf.text("BYN", x: 126, y: 297)
        return pdf
    }

    static func parseWallet(_ pdf: PDFFixture) throws -> ParsedStatement {
        let document = try PDFStatementReader.document(from: pdf.data(), fileName: "oplati.pdf")
        return try OplatiParser().parse(document)
    }

    @Test("Оплати: приход и расход, описание из деталей, Id операции как ссылка")
    func walletRows() throws {
        let statement = try Self.parseWallet(Self.wallet())
        #expect(statement.rows.map(\.amount.minorUnits) == [-110, 5_000, -1_281, -500])
        #expect(statement.rows.map(\.description) == [
            "Оплата товаров/услуг TEST TRANSPORT",
            "Пополнение электронного кошелька с текущего счета BY00BLBB00000000000000000000, 50 р.",
            "Оплата в ЕРИП",
            "Перевод: Перечисление средств с электронного кошелька на банковскую карту ОАО \"Белинвестбанк\" 000000******1234",
        ])
        #expect(statement.rows.map(\.bankReference) == [
            "oplati:600000001", "oplati:600000002", "oplati:600000003", "oplati:600000004",
        ])
        #expect(statement.accountHint == AccountHint(currency: .byn))
        #expect(statement.openingBalance == Money(minorUnits: 380, currency: .byn))
        #expect(statement.closingBalance == Money(minorUnits: 3_489, currency: .byn))
        #expect(statement.warnings.isEmpty, "\(statement.warnings)")
        let components = Self.minsk.dateComponents([.month, .day, .hour, .minute], from: statement.rows[0].bookedAt)
        #expect(components == DateComponents(month: 8, day: 11, hour: 18, minute: 3))
    }

    @Test("Оплати: пополнение с карты и вывод на карту склеиваются с операциями карты в переводы")
    func walletTransfers() throws {
        let rows = try Self.parseWallet(Self.wallet()).rows
        let wallet = Account.ID()
        let card = Account.ID()
        func transaction(_ row: ParsedRow, on account: Account.ID) -> FinanceTransaction {
            FinanceTransaction(
                accountID: account, bookedAt: row.bookedAt, amount: row.amount,
                merchantRaw: row.description, mcc: row.mcc, source: .imported
            )
        }
        // Вторые стороны на карте: как их назовёт выписка карты, не важно, лишь бы со словом перевода.
        let topUp = transaction(rows[1], on: wallet)
        let withdrawal = transaction(rows[3], on: wallet)
        let cardDebit = FinanceTransaction(
            accountID: card, bookedAt: topUp.bookedAt, amount: Money(minorUnits: -5_000, currency: .byn),
            merchantRaw: "Перевод на электронный кошелек", source: .imported
        )
        let cardCredit = FinanceTransaction(
            accountID: card, bookedAt: withdrawal.bookedAt, amount: Money(minorUnits: 500, currency: .byn),
            merchantRaw: "Зачисление перевода с электронного кошелька", source: .imported
        )
        let pairs = TransferMatcher.pairs(in: [topUp, withdrawal, cardDebit, cardCredit])
        #expect(Set(pairs.map(\.incoming)) == [topUp.id, cardCredit.id])
        #expect(Set(pairs.map(\.outgoing)) == [cardDebit.id, withdrawal.id])
    }

    @Test("Оплати: если обороты не сходятся, парсер предупреждает")
    func walletMismatch() throws {
        let warnings = try Self.parseWallet(Self.wallet(expense: "15.00")).warnings.map(\.message)
        #expect(warnings.contains { $0.hasPrefix("Сумма операций не сходится") })
    }

    @Test("Карту и кошелёк не путают ни между собой, ни с другими банками")
    func confidence() throws {
        let card = try PDFStatementReader.document(from: Self.card().data(), fileName: "a.pdf")
        let wallet = try PDFStatementReader.document(from: Self.wallet().data(), fileName: "b.pdf")
        #expect(BelinvestbankParser().confidence(for: card) >= 0.9)
        #expect(OplatiParser().confidence(for: wallet) >= 0.9)
        #expect(OplatiParser().confidence(for: card) < BelinvestbankParser().confidence(for: card))
        #expect(BelinvestbankParser().confidence(for: wallet) < OplatiParser().confidence(for: wallet))
        for other in [PriorbankParser(), BelarusbankParser(), AlfabankParser()] as [any StatementParser] {
            #expect(other.confidence(for: card) < 0.3)
            #expect(other.confidence(for: wallet) < 0.3)
        }
        let alfa = try PDFStatementReader.document(from: AlfabankParserTests.statement().data(), fileName: "c.pdf")
        #expect(BelinvestbankParser().confidence(for: alfa) < 0.3)
        #expect(OplatiParser().confidence(for: alfa) < 0.3)
    }

    @Test("В списке банков только те, у которых есть парсер")
    func banks() {
        #expect(BankParsersBY.banks.map(\.id) == BankParsersBY.all.map(\.bank.id))
        #expect(!BankParsersBY.banks.contains { $0.id == "by.sberbank" })
    }
}
