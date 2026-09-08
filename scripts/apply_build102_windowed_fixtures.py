"""Build 102: replace multi-day iPhone fixture bursts with one canonical window call.

This runs after the proven release/canonical transformations. The window endpoint
returns the same canonical match model (np: IDs). On any window failure, the
existing day-by-day canonical path remains as a fallback.
"""
from pathlib import Path


def replace_once(text, old, new, label):
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f"Build 102 patch marker missing: {label}")
    return text.replace(old, new, 1)

client = Path("Sources/Core/CanonicalSportsClient.swift")
s = client.read_text()

response_anchor = "    struct Match: Decodable {"
window_response = '''    struct WindowResponse: Decodable {
        let from: String
        let to: String
        let timezone: String
        let generatedAt: String?
        let matches: [Match]
        let meta: FixturesResponse.Meta?
    }

'''
if window_response.strip() not in s:
    if response_anchor not in s:
        raise SystemExit("Build 102 patch marker missing: window response anchor")
    s = s.replace(response_anchor, window_response + response_anchor, 1)

method_anchor = '''    static func detail(matchID: String, date: Date? = nil) async throws -> MatchDetail {'''
window_method = '''    static func window(from: Date, to: Date, teamID: String? = nil, leagueID: String? = nil, season: Int? = nil) async throws -> WindowResponse {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        var query = [
            URLQueryItem(name: "from", value: formatter.string(from: from)),
            URLQueryItem(name: "to", value: formatter.string(from: to))
        ]
        if let teamID { query.append(.init(name: "team", value: teamID)) }
        if let leagueID { query.append(.init(name: "league", value: leagueID)) }
        if let season { query.append(.init(name: "season", value: String(season))) }
        return try await get("api/v2/window", query: query)
    }

'''
if window_method.strip() not in s:
    if method_anchor not in s:
        raise SystemExit("Build 102 patch marker missing: detail method anchor")
    s = s.replace(method_anchor, window_method + method_anchor, 1)
client.write_text(s)

store = Path("Sources/Core/APISportsStore.swift")
s = store.read_text()

old_league = '''    func leagueFixtures(leagueID: String, count: Int = 20) async throws -> [APIPlusMatch] {
        let calendar = SportsDisplayDate.calendar
        let today = calendar.startOfDay(for: Date())
        var output: [APIPlusMatch] = []
        for start in stride(from: -7, through: 7, by: 3) {
            try Task.checkCancellation()
            let offsets = Array(start...min(start + 2, 7))
            let batch = await withTaskGroup(of: [APIPlusMatch].self) { group in
                for offset in offsets { if let day = calendar.date(byAdding: .day, value: offset, to: today) { group.addTask { (try? await self.fixtures(date: day)) ?? [] } } }
                var values: [APIPlusMatch] = []
                for await matches in group { values.append(contentsOf: matches.filter { $0.leagueID == leagueID }) }
                return values
            }
            output.append(contentsOf: batch)
        }
        var seen = Set<String>()
        return output.filter { seen.insert($0.id).inserted }.sorted { a, b in
            let phaseA = FixturePhase.isFinished(a.status) ? 1 : 0
            let phaseB = FixturePhase.isFinished(b.status) ? 1 : 0
            if phaseA != phaseB { return phaseA < phaseB }
            return phaseA == 0 ? (a.date ?? .distantFuture) < (b.date ?? .distantFuture) : (a.date ?? .distantPast) > (b.date ?? .distantPast)
        }
    }'''
new_league = '''    func leagueFixtures(leagueID: String, count: Int = 20) async throws -> [APIPlusMatch] {
        let calendar = SportsDisplayDate.calendar
        let today = calendar.startOfDay(for: Date())
        let from = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let to = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        do {
            let window = try await CanonicalSportsClient.window(from: from, to: to, leagueID: leagueID, season: APIFootballClient.currentSeason)
            try Task.checkCancellation()
            var seen = Set<String>()
            return window.matches.map(\\.appMatch).filter { seen.insert($0.id).inserted }.sorted { a, b in
                let phaseA = FixturePhase.isFinished(a.status) ? 1 : 0
                let phaseB = FixturePhase.isFinished(b.status) ? 1 : 0
                if phaseA != phaseB { return phaseA < phaseB }
                return phaseA == 0 ? (a.date ?? .distantFuture) < (b.date ?? .distantFuture) : (a.date ?? .distantPast) > (b.date ?? .distantPast)
            }
        } catch {
            if error is CancellationError { throw error }
            return try await legacyLeagueFixtures(leagueID: leagueID)
        }
    }
    private func legacyLeagueFixtures(leagueID: String) async throws -> [APIPlusMatch] {
        let calendar = SportsDisplayDate.calendar
        let today = calendar.startOfDay(for: Date())
        var output: [APIPlusMatch] = []
        for start in stride(from: -7, through: 7, by: 3) {
            try Task.checkCancellation()
            let offsets = Array(start...min(start + 2, 7))
            let batch = await withTaskGroup(of: [APIPlusMatch].self) { group in
                for offset in offsets { if let day = calendar.date(byAdding: .day, value: offset, to: today) { group.addTask { (try? await self.fixtures(date: day)) ?? [] } } }
                var values: [APIPlusMatch] = []
                for await matches in group { values.append(contentsOf: matches.filter { $0.leagueID == leagueID }) }
                return values
            }
            output.append(contentsOf: batch)
        }
        var seen = Set<String>()
        return output.filter { seen.insert($0.id).inserted }.sorted { a, b in
            let phaseA = FixturePhase.isFinished(a.status) ? 1 : 0
            let phaseB = FixturePhase.isFinished(b.status) ? 1 : 0
            if phaseA != phaseB { return phaseA < phaseB }
            return phaseA == 0 ? (a.date ?? .distantFuture) < (b.date ?? .distantFuture) : (a.date ?? .distantPast) > (b.date ?? .distantPast)
        }
    }'''
s = replace_once(s, old_league, new_league, "league window")

old_team = '''    func teamFixtures(teamID: String, teamName: String? = nil, next: Bool) async throws -> [APIPlusMatch] {
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
        let calendar = SportsDisplayDate.calendar
        let today = calendar.startOfDay(for: Date())
        let from = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let to = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        do {
            let window = try await CanonicalSportsClient.window(from: from, to: to, teamID: teamID)
            try Task.checkCancellation()
            var seen = Set<String>()
            return window.matches.map(\\.appMatch).filter { match in
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
s = replace_once(s, old_team, new_team, "team window")
store.write_text(s)

print("Build 102 canonical windowed fixture client applied")
