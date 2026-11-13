import Domain
import Foundation
import GRDB

extension AppDatabase {
    /// Снимок базы в файл через backup API SQLite: согласован, даже если идёт запись.
    func exportBackup(to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let destination = try DatabaseQueue(path: url.path)
        try writer.backup(to: destination)
        try destination.close()
    }

    /// Восстановление из копии. Сначала копия проверяется и мигрирует во временном файле,
    /// и только потом её содержимое заменяет текущую базу (тоже через backup API, одной операцией).
    func restoreBackup(from url: URL) throws {
        let fileManager = FileManager.default
        let temporary = fileManager.temporaryDirectory.appendingPathComponent("restore-\(UUID().uuidString).sqlite")
        try fileManager.copyItem(at: url, to: temporary)
        defer { try? fileManager.removeItem(at: temporary) }

        let source: DatabaseQueue
        do {
            source = try DatabaseQueue(path: temporary.path)
            try source.read { db in
                guard try db.tableExists("accounts"), try db.tableExists("transactions") else {
                    throw BackupError.notBackup
                }
            }
        } catch let error as BackupError {
            throw error
        } catch {
            // Не SQLite или повреждённый файл.
            throw BackupError.notBackup
        }
        // Копию никогда не стираем при расхождении схемы, даже в отладочной сборке.
        var migrator = Self.migrator
        migrator.eraseDatabaseOnSchemaChange = false
        if try source.read({ try migrator.hasBeenSuperseded($0) }) {
            throw BackupError.newerVersion
        }
        try migrator.migrate(source)
        try source.backup(to: writer)
        try source.close()
        // Backup API не проходит через отслеживание изменений: экраны узнают о новой базе отсюда.
        try writer.write { db in try db.notifyChanges(in: .fullDatabase) }
    }
}

/// Резервные копии базы приложения.
public struct GRDBBackupService: BackupService {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func exportBackup(to url: URL) async throws {
        let database = database
        try await Task.detached(priority: .userInitiated) { try database.exportBackup(to: url) }.value
    }

    public func restoreBackup(from url: URL) async throws {
        let database = database
        try await Task.detached(priority: .userInitiated) { try database.restoreBackup(from: url) }.value
    }
}
