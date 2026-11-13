import Domain
import Foundation

/// Загружает недостающие курсы НБ РБ и кладёт их в кэш в базе (#10).
///
/// Ошибки сети не пробрасываются: без курса аналитика просто остаётся приблизительной
/// (ближайший известный курс), а курс догрузится при следующем открытии экрана.
public struct ExchangeRateLoader: Sendable {
    /// Сколько BYN стоит единица валюты на день `yyyy-MM-dd`.
    public typealias Fetch = @Sendable (Currency, String) async throws -> Decimal

    private let fetch: Fetch
    private let repository: any ExchangeRateRepository
    /// Сколько запросов к API одновременно.
    private let concurrency: Int

    public init(repository: any ExchangeRateRepository, concurrency: Int = 4, fetch: @escaping Fetch) {
        self.repository = repository
        self.concurrency = max(1, concurrency)
        self.fetch = fetch
    }

    public init(repository: any ExchangeRateRepository, provider: NBRBExchangeRateProvider = NBRBExchangeRateProvider()) {
        self.init(repository: repository) { currency, day in
            try await provider.bynRate(for: currency, day: day)
        }
    }

    /// Загружает курсы и сохраняет те, что удалось получить.
    /// - Returns: сколько курсов сохранено.
    @discardableResult
    public func load(_ keys: Set<ExchangeRateKey>) async -> Int {
        let pending = keys.filter { $0.currency != .byn }.sorted()
        guard !pending.isEmpty else { return 0 }
        var loaded: [ExchangeRateKey: Decimal] = [:]
        let fetch = self.fetch
        await withTaskGroup(of: (ExchangeRateKey, Decimal?).self) { group in
            var iterator = pending.makeIterator()
            for _ in 0..<concurrency {
                guard let key = iterator.next() else { break }
                group.addTask { (key, try? await fetch(key.currency, key.day)) }
            }
            while let result = await group.next() {
                if let rate = result.1, rate > 0 { loaded[result.0] = rate }
                if let key = iterator.next() {
                    group.addTask { (key, try? await fetch(key.currency, key.day)) }
                }
            }
        }
        do {
            try await repository.save(loaded)
        } catch {
            return 0
        }
        return loaded.count
    }
}
