// Reuses the production comparison coordinator without SwiftUI or live providers.
import Foundation

protocol ObservableObject {}
@propertyWrapper struct Published<Value> { var wrappedValue: Value }
struct APIPlusPlayer: Equatable { let id: String; let name: String }
struct APIPlusPlayerSeasonStat: Equatable { let id: String }
enum ComparisonTestError: Error { case network }

@MainActor final class APISportsStore {
    static let shared = APISportsStore()
    var next = 0
    var searches: [Int: CheckedContinuation<[APIPlusPlayer], Error>] = [:]
    var statistics: [Int: CheckedContinuation<[APIPlusPlayerSeasonStat], Error>] = [:]
    func searchPlayers(_ text: String) async throws -> [APIPlusPlayer] {
        let id = next; next += 1
        return try await withCheckedThrowingContinuation { searches[id] = $0 }
    }
    func playerSeasonStats(playerID: String) async throws -> [APIPlusPlayerSeasonStat] {
        let id = next; next += 1
        return try await withCheckedThrowingContinuation { statistics[id] = $0 }
    }
    func wait(_ id: Int, stats: Bool) async throws {
        for _ in 0..<500 {
            if stats ? statistics[id] != nil : searches[id] != nil { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        fatalError("request never started")
    }
}

// INJECT_PRODUCTION_COMPARISON_CLASS

@main struct V2ComparisonTests {
    @MainActor static var checks = 0
    @MainActor static func check(_ condition: Bool, _ message: String) {
        checks += 1
        guard condition else { fatalError(message) }
    }
    @MainActor static func start(_ model: V2ComparisonSide, stats: Bool) async throws -> (Task<Void, Never>, Int) {
        let id = APISportsStore.shared.next
        let task = Task { if stats { await model.loadStats() } else { await model.search() } }
        try await APISportsStore.shared.wait(id, stats: stats)
        return (task, id)
    }
    @MainActor static func main() async throws {
        let api = APISportsStore.shared
        let a = APIPlusPlayer(id: "1", name: "Player A")
        let b = APIPlusPlayer(id: "2", name: "Player B")
        // Same selection keeps a completed value and the request already in flight.
        do {
            let model = V2ComparisonSide(); model.choose(a)
            let (first, id) = try await start(model, stats: true)
            model.choose(a)
            check(model.stats.isLoading, "same-ID selection cleared active stats")
            api.statistics.removeValue(forKey: id)!.resume(returning: [.init(id: "a-season")]); await first.value
            model.choose(a)
            check(model.selectedStat?.id == "a-season", "same-ID selection cleared completed stats")
            let (retry, retryID) = try await start(model, stats: true)
            api.statistics.removeValue(forKey: retryID)!.resume(throwing: ComparisonTestError.network); await retry.value
            check(model.selectedStat?.id == "a-season" && model.stats.errorMessage != nil && !model.stats.isLoading, "failed refresh must retain usable stats with retry error")
        }
        // Switching player rejects the old response and old cleanup.
        do {
            let model = V2ComparisonSide(); model.choose(a)
            let (old, oldID) = try await start(model, stats: true)
            model.choose(b)
            let (new, newID) = try await start(model, stats: true)
            api.statistics.removeValue(forKey: oldID)!.resume(returning: [.init(id: "old")]); await old.value
            check(model.player == b && model.stats.isLoading && model.selectedStat == nil, "old player overwrote newer request")
            api.statistics.removeValue(forKey: newID)!.resume(returning: [.init(id: "b-season")]); await new.value
            check(model.selectedStat?.id == "b-season" && !model.stats.isLoading, "new player did not finish")
        }
        // Two requests for the same player: stale success cannot beat the latest.
        do {
            let model = V2ComparisonSide(); model.choose(a)
            let (old, oldID) = try await start(model, stats: true)
            let (new, newID) = try await start(model, stats: true)
            api.statistics.removeValue(forKey: newID)!.resume(returning: [.init(id: "latest")]); await new.value
            api.statistics.removeValue(forKey: oldID)!.resume(returning: [.init(id: "stale")]); await old.value
            check(model.selectedStat?.id == "latest", "out-of-order success changed selected record")
        }
        // Cancellation leaves a retryable model and never applies cancelled data.
        do {
            let model = V2ComparisonSide(); model.choose(a)
            let (old, oldID) = try await start(model, stats: true)
            old.cancel(); api.statistics.removeValue(forKey: oldID)!.resume(returning: [.init(id: "cancelled")]); await old.value
            check(!model.stats.isLoading && model.selectedStat == nil, "cancelled stats were accepted or left loading")
            let (retry, id) = try await start(model, stats: true)
            api.statistics.removeValue(forKey: id)!.resume(returning: []); await retry.value
            check(model.stats.value == [] && model.stats.errorMessage == nil, "empty success must remain distinct from failure")
        }
        // Search identity uses the normalized input, and older queries cannot win.
        do {
            let model = V2ComparisonSide()
            let long = String(repeating: "a", count: 100); model.edit(long)
            let (old, oldID) = try await start(model, stats: false)
            model.edit(long + "b")
            check(model.results.isLoading && model.query == long, "equivalent truncated input reset active search")
            model.edit("next")
            let (new, newID) = try await start(model, stats: false)
            api.searches.removeValue(forKey: oldID)!.resume(returning: [a]); await old.value
            check(model.results.value == nil && model.results.isLoading, "old query affected new search")
            api.searches.removeValue(forKey: newID)!.resume(returning: [b]); await new.value
            check(model.results.value == [b], "new search results missing")
            model.choose(b)
            check(model.results.value == nil && model.player == b, "selection did not clear search results")
            model.choose(nil)
            check(model.query.isEmpty && model.player == nil && model.stats.value == nil, "clear selection failed")
        }
        // Two comparison panes own completely separate resources.
        do {
            let left = V2ComparisonSide(), right = V2ComparisonSide()
            left.choose(a); right.choose(b)
            let (l, lid) = try await start(left, stats: true)
            let (r, rid) = try await start(right, stats: true)
            api.statistics.removeValue(forKey: lid)!.resume(throwing: ComparisonTestError.network); await l.value
            check(left.stats.errorMessage != nil && right.stats.isLoading, "left failure affected right")
            api.statistics.removeValue(forKey: rid)!.resume(returning: [.init(id: "right")]); await r.value
            check(right.selectedStat?.id == "right", "right pane failed")
        }
        check(api.searches.isEmpty && api.statistics.isEmpty, "leaked test requests")
        print("Production comparison coordinator: 7 scenarios, \(checks) assertions passed")
    }
}
