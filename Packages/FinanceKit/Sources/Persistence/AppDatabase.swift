import Foundation
import GRDB

/// Точка входа в SQLite-базу приложения: открывает файл и прогоняет миграции.
public final class AppDatabase: Sendable {
    let writer: any DatabaseWriter

    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// База в Application Support. На iOS файл защищён до первой разблокировки устройства.
    public static func onDisk(fileName: String = "moneytalks.sqlite") throws -> AppDatabase {
        let fileManager = FileManager.default
        let folder = try fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Database", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        #if os(iOS)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: folder.path
        )
        #endif
        let pool = try DatabasePool(path: folder.appendingPathComponent(fileName).path)
        return try AppDatabase(pool)
    }

    /// База в памяти для тестов и SwiftUI-превью.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    /// Оборачивает `ValueObservation` в `AsyncThrowingStream`, чтобы наружу не торчали типы GRDB.
    func stream<Reducer: ValueReducer>(
        _ observation: ValueObservation<Reducer>
    ) -> AsyncThrowingStream<Reducer.Value, any Error> where Reducer.Value: Sendable {
        let writer = self.writer
        return AsyncThrowingStream { continuation in
            let cancellable = observation.start(
                in: writer,
                scheduling: .async(onQueue: .main),
                onError: { continuation.finish(throwing: $0) },
                onChange: { continuation.yield($0) }
            )
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}
