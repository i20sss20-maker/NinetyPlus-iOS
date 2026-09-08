// The runner injects the production canonical loader; no networking or SwiftUI.
import Foundation

struct APIPlusMatch: Equatable {
    let id: String
    let score: Int
}
struct WrappedMatch { let appMatch: APIPlusMatch }
struct Detail {
    let match: WrappedMatch
    let appEvents: [Int]
    let appStatistics: [Int]
    let appLineups: [Int]
    init(_ match: APIPlusMatch) {
        self.match = WrappedMatch(appMatch: match)
        appEvents = [match.score]; appStatistics = [match.score]; appLineups = [match.score]
    }
}
enum TestFailure: Error { case assertion(String), network }
func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw TestFailure.assertion(message) }
}

@MainActor enum CanonicalSportsClient {
    static var nextID = 0
    static var pending: [Int: CheckedContinuation<Detail, Error>] = [:]
    static func detail(matchID: String) async throws -> Detail {
        let id = nextID; nextID += 1
        return try await withCheckedThrowingContinuation { pending[id] = $0 }
    }
    static func wait(_ id: Int) async throws {
        for _ in 0..<10000 {
            if pending[id] != nil { return }
            await Task.yield()
        }
        throw TestFailure.assertion("request did not start")
    }
    static func complete(_ id: Int, with match: APIPlusMatch) {
        pending.removeValue(forKey: id)!.resume(returning: Detail(match))
    }
    static func fail(_ id: Int) {
        pending.removeValue(forKey: id)!.resume(throwing: TestFailure.network)
    }
}

@MainActor final class TestStore {
    var progress = MatchCenterProgress()
    var current: APIPlusMatch?
    var lastObserved: APIPlusMatch?
    var events: [Int] = []
    var stats: [Int] = []
    var lineups: [Int] = []
    func prepare(_ match: APIPlusMatch) {
        guard progress.select(matchID: match.id) else { return }
        current = match; lastObserved = nil
        events = []; stats = []; lineups = []
    }
    // INJECT_PRODUCTION_CANONICAL_METHOD
}

@main struct CanonicalRecoveryTests {
    @MainActor static func start(_ store: TestStore, _ match: APIPlusMatch, force: Bool = false) async throws -> (Task<Void, Never>, Int) {
        let id = CanonicalSportsClient.nextID
        let task = Task { await store.loadCanonical(match, force: force) }
        try await CanonicalSportsClient.wait(id)
        return (task, id)
    }
    @MainActor static func idle(_ store: TestStore) -> Bool {
        [MatchDataSection.fixture, .events, .stats, .lineups].allSatisfy { !store.progress.state($0).isLoading }
    }
    @MainActor static func run() async throws {
        let seed = APIPlusMatch(id: "np:test", score: 0)
        let fresh = APIPlusMatch(id: "np:test", score: 2)
        var passed = 0
        // 1. Success survives cleanup; no data or timestamps are discarded.
        do {
            let store = TestStore()
            let (task, id) = try await start(store, seed)
            CanonicalSportsClient.complete(id, with: fresh); await task.value
            try expect(store.current == fresh && idle(store), "success must update data and release loading")
            try expect(store.progress.state(.fixture).lastUpdated != nil, "success needs a timestamp")
            try expect(store.events == [2] && store.stats == [2] && store.lineups == [2], "success must retain detail")
            passed += 1
        }
        // 2. First failure keeps the card snapshot but cannot claim freshness.
        do {
            let store = TestStore()
            let (task, id) = try await start(store, seed)
            CanonicalSportsClient.fail(id); await task.value
            let fixture = store.progress.state(.fixture)
            try expect(store.current == seed && idle(store), "failure must preserve header")
            try expect(fixture.value == nil && fixture.lastUpdated == nil && fixture.errorMessage == nil, "failed first load must not fabricate a successful refresh")
            try expect(store.progress.state(.events).errorMessage != nil, "detail retry error must remain")
            passed += 1
        }
        // 3. A failed refresh cannot advance the last successful timestamp.
        do {
            let store = TestStore()
            let (first, a) = try await start(store, seed)
            CanonicalSportsClient.complete(a, with: fresh); await first.value
            let timestamp = store.progress.state(.fixture).lastUpdated
            let (second, b) = try await start(store, seed, force: true)
            CanonicalSportsClient.fail(b); await second.value
            try expect(store.current == fresh && store.events == [2], "failed refresh must retain cached content")
            try expect(store.progress.state(.fixture).lastUpdated == timestamp, "failed refresh changed freshness")
            try expect(idle(store), "failed refresh must release loading")
            passed += 1
        }
        // 4. Cancellation must free tokens so a retry can actually start.
        do {
            let store = TestStore()
            let (task, id) = try await start(store, seed)
            task.cancel(); CanonicalSportsClient.complete(id, with: fresh); await task.value
            try expect(idle(store), "cancelled request left the page loading")
            try expect(store.progress.state(.fixture).lastUpdated == nil, "cancelled response was applied")
            let (retry, retryID) = try await start(store, seed)
            CanonicalSportsClient.complete(retryID, with: fresh); await retry.value
            try expect(store.current == fresh && idle(store), "retry after cancellation failed")
            passed += 1
        }
        // 5. Old cancellation cleanup cannot cancel a newer forced refresh.
        do {
            let store = TestStore()
            let (old, a) = try await start(store, seed)
            let (new, b) = try await start(store, seed, force: true)
            old.cancel(); CanonicalSportsClient.complete(a, with: seed); await old.value
            try expect(store.progress.state(.fixture).isLoading, "old cleanup cancelled newer refresh")
            CanonicalSportsClient.complete(b, with: fresh); await new.value
            try expect(store.current == fresh && idle(store), "new refresh did not finish")
            passed += 1
        }
        // 6. Responses and cleanup for another match cannot overwrite its page.
        do {
            let store = TestStore()
            let other = APIPlusMatch(id: "np:other", score: 7)
            let (old, a) = try await start(store, seed)
            let (new, b) = try await start(store, other)
            CanonicalSportsClient.complete(a, with: fresh); await old.value
            try expect(store.current == other && store.progress.state(.fixture).isLoading, "old match affected new match")
            CanonicalSportsClient.complete(b, with: other); await new.value
            try expect(store.current == other && idle(store), "other match did not finish")
            passed += 1
        }
        // 7. Concurrent non-forced calls share the in-flight state, not tokens.
        do {
            let store = TestStore()
            let (first, a) = try await start(store, seed)
            let count = CanonicalSportsClient.nextID
            await store.loadCanonical(seed, force: false)
            try expect(CanonicalSportsClient.nextID == count, "duplicate request was sent")
            try expect(store.progress.state(.fixture).isLoading, "duplicate call cleared active loading")
            CanonicalSportsClient.complete(a, with: fresh); await first.value
            try expect(idle(store), "shared request did not finish")
            passed += 1
        }
        try expect(CanonicalSportsClient.pending.isEmpty, "test leaked a continuation")
        print("Canonical recovery Swift scenarios: \(passed)/7 passed")
    }
    static func main() async {
        do { try await run() }
        catch { print("FAILED: \(error)"); exit(1) }
    }
}
