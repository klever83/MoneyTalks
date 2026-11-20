import Domain
import Foundation
import GRDB
@testable import Persistence
import Testing

@Suite("Миграция новых системных категорий")
struct SystemCategoriesMigrationTests {
    @Test("Список категорий v9 не меняется: новые категории идут со своей миграцией")
    func addedListIsFrozen() {
        // Кто уже прошёл v9, дописанную сюда категорию не получит. Если тест упал, заведи
        // новый список и миграцию `v10-…`, а этот верни как был.
        #expect(SystemCategories.added.compactMap(\.systemKey) == [
            "marketplaces", "beauty", "sport", "home", "electronics", "betting", "fees", "interest",
        ])
    }

    @Test("Установленное приложение получает новые категории в конце списка, повтор ничего не дублирует")
    func addsCategoriesToExistingDatabase() throws {
        let queue = try DatabaseQueue()
        let migrator = AppDatabase.migrator
        try migrator.migrate(queue, upTo: "v8-transactions-date-index")
        let before = try queue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories") ?? 0 }
        let lastSort = try queue.read { db in try Int.fetchOne(db, sql: "SELECT MAX(sortOrder) FROM categories") ?? 0 }
        // Старые установки: категории первой версии, без добавленных.
        #expect(before == SystemCategories.all.count)

        // Имитация старой базы: убираем то, что `v1` уже вставила из обновлённого списка.
        try queue.write { db in
            for category in SystemCategories.added {
                try db.execute(sql: "DELETE FROM categories WHERE id = ?", arguments: [category.id.rawValue])
            }
        }
        try migrator.migrate(queue)

        let keys = try queue.read { db in
            try String.fetchAll(db, sql: "SELECT systemKey FROM categories WHERE systemKey IS NOT NULL")
        }
        #expect(Set(keys) == Set(SystemCategories.all.compactMap(\.systemKey)))
        #expect(keys.count == SystemCategories.all.count)
        let addedSorts = try queue.read { db in
            try Int.fetchAll(
                db,
                sql: "SELECT sortOrder FROM categories WHERE systemKey IN (\(SystemCategories.added.map { _ in "?" }.joined(separator: ",")))",
                arguments: StatementArguments(SystemCategories.added.compactMap(\.systemKey))
            )
        }
        #expect(addedSorts.allSatisfy { $0 > lastSort - SystemCategories.added.count })
        #expect(Set(addedSorts).count == SystemCategories.added.count)
    }

    @Test("Прошедшие v9 получают «Переводы людям» миграцией v10")
    func addsTransfersToPeople() throws {
        let queue = try DatabaseQueue()
        let migrator = AppDatabase.migrator
        try migrator.migrate(queue, upTo: "v9-more-system-categories")
        try queue.write { db in
            for category in SystemCategories.addedV10 {
                try db.execute(sql: "DELETE FROM categories WHERE id = ?", arguments: [category.id.rawValue])
            }
        }
        try migrator.migrate(queue)
        let keys = try queue.read { db in
            try String.fetchAll(db, sql: "SELECT systemKey FROM categories WHERE systemKey IS NOT NULL")
        }
        #expect(keys.contains("transfers_people"))
        #expect(keys.count == SystemCategories.all.count)
    }
}
