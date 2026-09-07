import Foundation

/// Each followed club owns its result and request token. One failed club cannot
/// erase another club's fixtures, or turn a failed request into an empty success.
struct ForYouProgress<Item> {
    private(set) var teamIDs: [String] = []
    private var resources: [String: PageResource<[Item]>] = [:]

    mutating func select(_ ids: [String]) {
        let selected = Array(Set(ids.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })).sorted()
        guard selected != teamIDs else { return }
        invalidate()
        teamIDs = selected
        resources = resources.filter { selected.contains($0.key) }
        for id in selected where resources[id] == nil { resources[id] = PageResource<[Item]>() }
    }

    func state(_ id: String) -> PageResource<[Item]> { resources[id] ?? PageResource<[Item]>() }
    var values: [Item] { teamIDs.flatMap { resources[$0]?.value ?? [] } }
    var hasValue: Bool { teamIDs.contains { resources[$0]?.value != nil } }
    var isLoading: Bool { teamIDs.contains { resources[$0]?.isLoading == true } }
    var failures: [String] { teamIDs.filter { resources[$0]?.errorMessage != nil } }
    var mayShowEmpty: Bool {
        !teamIDs.isEmpty && teamIDs.allSatisfy {
            let resource = state($0)
            return resource.value != nil && !resource.isLoading && resource.errorMessage == nil
        }
    }
    // The oldest successful club refresh is more honest than the newest one.
    var lastUpdated: Date? { teamIDs.compactMap { resources[$0]?.lastUpdated }.min() }

    func pendingIDs(force: Bool = false, now: Date = Date()) -> [String] {
        teamIDs.filter {
            let resource = state($0)
            return !resource.isLoading && (force || !resource.isFresh(key: $0, maxAge: 300, now: now))
        }
    }

    mutating func begin(_ id: String, force: Bool = false, now: Date = Date()) -> UUID? {
        guard teamIDs.contains(id), pendingIDs(force: force, now: now).contains(id) else { return nil }
        return resources[id]?.begin(key: id)
    }

    @discardableResult
    mutating func succeed(_ id: String, items: [Item], token: UUID, at date: Date = Date()) -> Bool {
        resources[id]?.succeed(items, token: token, at: date) ?? false
    }

    @discardableResult
    mutating func fail(_ id: String, message: String, token: UUID) -> Bool {
        resources[id]?.fail(message, token: token) ?? false
    }

    mutating func cancel(_ id: String, token: UUID) { resources[id]?.cancel(token: token) }
    mutating func invalidate() {
        for id in teamIDs { resources[id]?.invalidate() }
    }
}

protocol FollowedMatchSummary {
    var id: String { get }
    var homeID: String? { get }
    var awayID: String? { get }
    var date: Date? { get }
    var status: String { get }
}

enum ForYouMatchSelection {
    static func merge<Match: FollowedMatchSummary>(
        today: [Match], upcoming: [Match], teamIDs: Set<String>,
        startOfToday: Date, isLive: (String) -> Bool
    ) -> [Match] {
        guard !teamIDs.isEmpty else { return [] }
        var byID: [String: Match] = [:]
        for match in upcoming {
            guard FixturePhase.isUpcoming(match.status) || isLive(match.status) else { continue }
            guard isLive(match.status) || (match.date.map { $0 >= startOfToday } ?? true) else { continue }
            byID[match.id] = match
        }
        // Today's response wins over an older cached upcoming copy of a match.
        for match in today { byID[match.id] = match }
        let selected = byID.values.filter { match in
            match.homeID.map { teamIDs.contains($0) } == true ||
                match.awayID.map { teamIDs.contains($0) } == true
        }
        func rank(_ match: Match) -> Int {
            if isLive(match.status) { return 0 }
            if FixturePhase.isUpcoming(match.status) { return 1 }
            if FixturePhase.isFinished(match.status) { return 2 }
            return 3
        }
        return selected.sorted { left, right in
            let a = rank(left), b = rank(right)
            if a != b { return a < b }
            let leftDate = left.date ?? (a == 2 ? .distantPast : .distantFuture)
            let rightDate = right.date ?? (b == 2 ? .distantPast : .distantFuture)
            if leftDate != rightDate { return a == 2 ? leftDate > rightDate : leftDate < rightDate }
            return left.id < right.id
        }
    }
}
