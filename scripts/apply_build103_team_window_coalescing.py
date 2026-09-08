"""Build 103: coalesce the club's previous/upcoming fixture loads.

V2TeamView requests recent and upcoming sections concurrently. Build 102 made each
section prefer the same ±7-day canonical window, so the two sections could still
race into duplicate window requests and duplicate degraded fallbacks. This pass
loads/caches one full club window and partitions it locally for both sections.
"""
from pathlib import Path


def replace_once(text, old, new, label):
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f"Build 103 patch marker missing: {label}")
    return text.replace(old, new, 1)

store = Path("Sources/Core/APISportsStore.swift")
s = store.read_text(encoding="utf-8")

state_old = '''    private var refreshBusy = false
    private var refreshedDay: String?
    private init() {}'''
state_new = '''    private var refreshBusy = false
    private var refreshedDay: String?
    private struct TeamWindowEntry { let fetchedAt: Date; let matches: [APIPlusMatch] }
    private var teamWindowCache: [String: TeamWindowEntry] = [:]
    private var teamWindowTasks: [String: Task<[APIPlusMatch], Error>] = [:]
    private init() {}'''
s = replace_once(s, state_old, state_new, "team window shared state")

old_team = '''    func teamFixtures(teamID: String, teamName: String? = nil, next: Bool) async throws -> [APIPlusMatch] {
        let calendar = SportsDisplayDate.calendar
        let today = calendar.startOfDay(for: Date())
        let from = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let to = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        do {
            let window = try await CanonicalSportsClient.window(from: from, to: to, teamID: teamID)
            try Task.checkCancellation()
            var seen = Set<String>()
            return window.matches.map(\.appMatch).filter { match in
                next ? (FixturePhase.isUpcoming(match.status) || isLive(match.status)) : FixturePhase.isFinished(match.status)
            }.filter { seen.insert($0.id).inserted }.sorted { a, b in
                next ? (a.date ?? .distantFuture) < (b.date ?? .distantFuture) : (a.date ?? .distantPast) > (b.date ?? .distantPast)
            }
        } catch {
            if error is CancellationError { throw error }
            return try await legacyTeamFixtures(teamID: teamID, teamName: teamName, next: next)
        }
    }
    private func legacyTeamFixtures(teamID: String, teamName: String?, next: Bool) async throws -> [APIPlusMatch] {
        let calendar = SportsDisplayDate.calendar
        let today = calendar.startOfDay(for: Date())
        let offsets = next ? Array(0...7) : Array(-7...0)
        var output: [APIPlusMatch] = []
        for start in stride(from: 0, to: offsets.count, by: 3) {
            try Task.checkCancellation()
            let batch = Array(offsets[start..<min(start + 3, offsets.count)])
            let values = await withTaskGroup(of: [APIPlusMatch].self) { group in
                for offset in batch { if let day = calendar.date(byAdding: .day, value: offset, to: today) { group.addTask { (try? await self.fixtures(date: day)) ?? [] } } }
                var values: [APIPlusMatch] = []
                for await matches in group { values.append(contentsOf: matches) }
                return values
            }
            output.append(contentsOf: values)
        }
        let normalizedName = teamName.map { SportsArabic.team($0) }
        var seen = Set<String>()
        return output.filter { match in
            let idMatch = match.homeID == teamID || match.awayID == teamID
            let nameMatch = normalizedName.map { SportsArabic.team(match.home) == $0 || SportsArabic.team(match.away) == $0 } ?? false
            guard idMatch || nameMatch else { return false }
            return next ? (FixturePhase.isUpcoming(match.status) || isLive(match.status)) : FixturePhase.isFinished(match.status)
        }.filter { seen.insert($0.id).inserted }.sorted { a, b in
            next ? (a.date ?? .distantFuture) < (b.date ?? .distantFuture) : (a.date ?? .distantPast) > (b.date ?? .distantPast)
        }
    }'''
new_team = '''    func teamFixtures(teamID: String, teamName: String? = nil, next: Bool) async throws -> [APIPlusMatch] {
        let all = try await teamFixtureWindow(teamID: teamID, teamName: teamName)
        try Task.checkCancellation()
        return all.filter { match in
            next ? (FixturePhase.isUpcoming(match.status) || isLive(match.status)) : FixturePhase.isFinished(match.status)
        }.sorted { a, b in
            next ? (a.date ?? .distantFuture) < (b.date ?? .distantFuture) : (a.date ?? .distantPast) > (b.date ?? .distantPast)
        }
    }
    private func teamFixtureWindow(teamID: String, teamName: String?) async throws -> [APIPlusMatch] {
        let calendar = SportsDisplayDate.calendar
        let today = calendar.startOfDay(for: Date())
        let key = "\(teamID):\(SharedFixtureDays.key(today))"
        if let entry = teamWindowCache[key], (0..<120).contains(Date().timeIntervalSince(entry.fetchedAt)) {
            return entry.matches
        }
        if let pending = teamWindowTasks[key] { return try await pending.value }
        let task = Task<[APIPlusMatch], Error> {
            let from = calendar.date(byAdding: .day, value: -7, to: today) ?? today
            let to = calendar.date(byAdding: .day, value: 7, to: today) ?? today
            do {
                let window = try await CanonicalSportsClient.window(from: from, to: to, teamID: teamID)
                try Task.checkCancellation()
                var seen = Set<String>()
                return window.matches.map(\.appMatch).filter { seen.insert($0.id).inserted }
            } catch {
                if error is CancellationError { throw error }
                return try await self.legacyTeamWindow(teamID: teamID, teamName: teamName)
            }
        }
        teamWindowTasks[key] = task
        do {
            let matches = try await task.value
            teamWindowTasks[key] = nil
            teamWindowCache[key] = TeamWindowEntry(fetchedAt: Date(), matches: matches)
            if teamWindowCache.count > 24,
               let oldest = teamWindowCache.min(by: { $0.value.fetchedAt < $1.value.fetchedAt })?.key { teamWindowCache[oldest] = nil }
            return matches
        } catch {
            teamWindowTasks[key] = nil
            throw error
        }
    }
    private func legacyTeamWindow(teamID: String, teamName: String?) async throws -> [APIPlusMatch] {
        let calendar = SportsDisplayDate.calendar
        let today = calendar.startOfDay(for: Date())
        let offsets = Array(-7...7)
        var output: [APIPlusMatch] = []
        for start in stride(from: 0, to: offsets.count, by: 3) {
            try Task.checkCancellation()
            let batch = Array(offsets[start..<min(start + 3, offsets.count)])
            let values = await withTaskGroup(of: [APIPlusMatch].self) { group in
                for offset in batch {
                    if let day = calendar.date(byAdding: .day, value: offset, to: today) {
                        group.addTask { (try? await self.fixtures(date: day)) ?? [] }
                    }
                }
                var values: [APIPlusMatch] = []
                for await matches in group { values.append(contentsOf: matches) }
                return values
            }
            output.append(contentsOf: values)
        }
        let normalizedName = teamName.map { SportsArabic.team($0) }
        var seen = Set<String>()
        return output.filter { match in
            let idMatch = match.homeID == teamID || match.awayID == teamID
            let nameMatch = normalizedName.map { SportsArabic.team(match.home) == $0 || SportsArabic.team(match.away) == $0 } ?? false
            return (idMatch || nameMatch) && seen.insert(match.id).inserted
        }
    }'''
s = replace_once(s, old_team, new_team, "coalesced team window")
store.write_text(s, encoding="utf-8")
print("Build 103 coalesced team window applied")

next_patch = Path("scripts/apply_build104_server_window_fallback.py")
if next_patch.exists():
    exec(compile(next_patch.read_text(encoding="utf-8"), str(next_patch), "exec"), {"__name__": "__main__"})
