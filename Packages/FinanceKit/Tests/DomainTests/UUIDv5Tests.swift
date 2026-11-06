import Domain
import Foundation
import Testing

@Suite("UUID v5 и ID системных категорий")
struct UUIDv5Tests {
    @Test("Совпадает с эталонным значением")
    func referenceVector() throws {
        let dns = try #require(UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8"))
        #expect(UUID(v5: "www.example.com", namespace: dns).uuidString == "2ED6657D-E927-568B-95E1-2665A8AEA6A2")
    }

    @Test("ID системной категории стабилен и уникален по ключу")
    func systemIDs() {
        #expect(FinanceCategory.systemID(for: "groceries") == FinanceCategory.systemID(for: "groceries"))
        #expect(FinanceCategory.systemID(for: "groceries") != FinanceCategory.systemID(for: "transport"))
    }
}
