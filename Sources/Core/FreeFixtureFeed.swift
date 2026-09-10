import Foundation

struct FixtureSnapshot: Codable {
    let matches: [APIPlusMatch]
    let fetchedAt: Date
    let warning: String?
}

actor FreeFixtureFeed {
    static let shared = FreeFixtureFeed()
    typealias Loader = @Sendable (Date, Bool) async throws -> [APIPlusMatch]
    private let loader: Loader
    private let defaults: UserDefaults
    private var cache: [String: FixtureSnapshot]
    private var pending: [String: Task<FixtureSnapshot, Error>] = [:]
    init(defaults: UserDefaults = .standard, loader: @escaping Loader = { date, force in
        try await PublicScoreboardSource.fixtures(date: date, force: force)
    }) {
        self.defaults = defaults; self.loader = loader
        cache = defaults.data(forKey: "free.fixtures.cache.v1")
            .flatMap { try? JSONDecoder().decode([String: FixtureSnapshot].self, from: $0) } ?? [:]
    }
    static func key(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = SportsDisplayDate.calendar; f.timeZone = f.calendar.timeZone; f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    func snapshot(date: Date, force: Bool = false, now: Date = Date()) async throws -> FixtureSnapshot {
        try Task.checkCancellation()
        let key = Self.key(date)
        let previous = cache[key]
        if !force, let previous, (0..<60).contains(now.timeIntervalSince(previous.fetchedAt)) { return previous }
        if let task = pending[key] { return try await task.value }
        let loader = self.loader
        let task = Task<FixtureSnapshot, Error> {
            do {
                let values = try await loader(date, force)
                return FixtureSnapshot(matches: values, fetchedAt: now, warning: nil)
            } catch {
                if error is CancellationError { throw error }
                if let previous, (0..<604800).contains(now.timeIntervalSince(previous.fetchedAt)) {
                    return FixtureSnapshot(matches: previous.matches, fetchedAt: previous.fetchedAt,
                        warning: "تعذر التحديث؛ هذه آخر بيانات محفوظة وليست نتيجة مباشرة الآن.")
                }
                throw error
            }
        }
        pending[key] = task
        defer { pending[key] = nil }
        let result = try await task.value
        if result.warning == nil {
            cache[key] = result
            while cache.count > 16, let oldest = cache.min(by: { $0.value.fetchedAt < $1.value.fetchedAt })?.key { cache[oldest] = nil }
            if let data = try? JSONEncoder().encode(cache) { defaults.set(data, forKey: "free.fixtures.cache.v1") }
        }
        try Task.checkCancellation()
        return result
    }
}
