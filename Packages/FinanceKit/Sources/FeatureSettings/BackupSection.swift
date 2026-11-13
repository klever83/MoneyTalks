import Domain
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Резервная копия базы (#69): сохранить в файл и восстановить из файла.
@MainActor
@Observable
final class BackupModel {
    private(set) var isWorking = false
    /// Готовая копия для системного экспорта файлов.
    var exportDocument: BackupDocument?
    /// Выбранный файл, ждёт подтверждения замены данных.
    var pendingRestore: URL?
    /// Итог операции для пользователя.
    var message: String?

    private let service: any BackupService

    init(service: any BackupService) {
        self.service = service
    }

    /// Имя файла копии: с датой, чтобы копии не путались.
    nonisolated static func fileName(on date: Date = .now) -> String {
        "MoneyTalks-\(ExchangeRateKey.day(for: date)).sqlite"
    }

    func prepareExport() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(Self.fileName())
        do {
            try await service.exportBackup(to: url)
            exportDocument = BackupDocument(url: url)
        } catch {
            message = String(localized: "Не удалось сохранить копию: \(error.localizedDescription)")
        }
    }

    func finishExport(_ result: Result<URL, any Error>) {
        if let url = exportDocument?.url { try? FileManager.default.removeItem(at: url) }
        exportDocument = nil
        switch result {
        case .success:
            message = String(localized: "Резервная копия сохранена.")
        case let .failure(error):
            // Отмена пользователем — не ошибка.
            if (error as? CocoaError)?.code != .userCancelled {
                message = String(localized: "Не удалось сохранить копию: \(error.localizedDescription)")
            }
        }
    }

    func restore() async {
        guard let url = pendingRestore, !isWorking else { return }
        pendingRestore = nil
        isWorking = true
        defer { isWorking = false }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            try await service.restoreBackup(from: url)
            message = String(localized: "Данные восстановлены из копии.")
        } catch BackupError.notBackup {
            message = String(localized: "Этот файл не резервная копия MoneyTalks.")
        } catch BackupError.newerVersion {
            message = String(localized: "Копия сделана более новой версией MoneyTalks. Обновите приложение и повторите.")
        } catch {
            message = String(localized: "Не удалось восстановить копию: \(error.localizedDescription)")
        }
    }
}

/// Файл копии для `fileExporter`: отдаёт уже записанный снимок базы.
struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.data]

    let url: URL

    init(url: URL) {
        self.url = url
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.featureUnsupported)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: url)
    }
}

struct BackupSection: View {
    @State private var model: BackupModel
    @State private var isImporting = false

    init(service: any BackupService) {
        _model = State(initialValue: BackupModel(service: service))
    }

    var body: some View {
        Section {
            Button("Сохранить резервную копию") {
                Task { await model.prepareExport() }
            }
            Button("Восстановить из копии") { isImporting = true }
        } header: {
            Text("Данные")
        } footer: {
            Text("Данные хранятся только на этом устройстве. Сохраняйте копию в Файлы или iCloud Drive, чтобы не потерять историю при смене телефона.")
        }
        .disabled(model.isWorking)
        .fileExporter(
            isPresented: Binding(get: { model.exportDocument != nil }, set: { if !$0 { model.exportDocument = nil } }),
            document: model.exportDocument,
            contentType: .data,
            defaultFilename: BackupModel.fileName()
        ) { result in
            model.finishExport(result)
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.data]) { result in
            if case let .success(url) = result { model.pendingRestore = url }
        }
        .confirmationDialog(
            "Заменить данные копией?",
            isPresented: Binding(get: { model.pendingRestore != nil }, set: { if !$0 { model.pendingRestore = nil } }),
            titleVisibility: .visible
        ) {
            Button("Заменить", role: .destructive) { Task { await model.restore() } }
        } message: {
            Text("Все счета, операции и настройки категорий на этом устройстве заменятся данными из копии.")
        }
        .alert(
            model.message ?? "",
            isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })
        ) {
            Button("OK", role: .cancel) {}
        }
    }
}
