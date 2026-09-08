import Foundation

struct APIPlusMatch: Identifiable, Hashable {
    let id: String; let leagueID: String?; let league: String; let leagueLogo: String?
    let homeID: String?; let home: String; let homeLogo: String?
    let awayID: String?; let away: String; let awayLogo: String?
    let homeScore: Int?; let awayScore: Int?; let date: Date?; let status: String; let elapsed: Int?
}
struct APIPlusTeam: Identifiable, Hashable {
    let id: String; let name: String; let country: String?; let founded: Int?; let logo: String?
    let venue: String?; let city: String?; let venueImage: String?
}
struct APIPlusPlayer: Identifiable, Hashable {
    let id: String; let name: String; let nationality: String?; let birth: String?
    let height: String?; let weight: String?; let photo: String?
}
struct APIPlusStanding: Identifiable, Hashable {
    let id: String; let rank: Int; let teamID: String; let team: String; let logo: String?
    let played: Int; let win: Int; let draw: Int; let lose: Int; let goalsFor: Int
    let goalsAgainst: Int; let goalDifference: Int; let points: Int; let form: String?
}
struct APIPlusScorer: Identifiable, Hashable {
    let id: String; let season: Int; let rank: Int; let playerID: String; let name: String; let photo: String?
    let nationality: String?; let teamID: String?; let team: String; let teamLogo: String?
    let appearances: Int; let minutes: Int; let goals: Int; let assists: Int
}

private actor SharedFixtureDays {
    static let shared = SharedFixtureDays()
    private struct Entry { let fetchedAt: Date; let fixtures: [APIFixture] }
    private var cache: [String: Entry] = [:]
    private var pending: [String: Task<[APIFixture], Error>] = [:]
    static func key(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = SportsDisplayDate.calendar
        formatter.timeZone = SportsDisplayDate.calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    func fetch(_ date: Date, force: Bool = false) async throws -> [APIFixture] {
        let key = Self.key(date)
        let ttl: TimeInterval = key == Self.key(Date()) ? AppRefreshPolicy.todayCacheTTL : 1800
        if !force, let entry = cache[key], (0..<ttl).contains(Date().timeIntervalSince(entry.fetchedAt)) { return entry.fixtures }
        if let task = pending[key] { return try await task.value }
        let task = Task<[APIFixture], Error> {
            let envelope: APIEnvelope<[APIFixture]> = try await APIFootballClient.get("fixtures", query: [
                .init(name: "date", value: key), .init(name: "timezone", value: "Asia/Riyadh")
            ])
            return envelope.response
        }
        pending[key] = task
        defer { pending[key] = nil }
        let fixtures = try await task.value
        if cache.count >= 24, cache[key] == nil,
           let oldest = cache.min(by: { $0.value.fetchedAt < $1.value.fetchedAt })?.key { cache[oldest] = nil }
        cache[key] = Entry(fetchedAt: Date(), fixtures: fixtures)
        return fixtures
    }
    func window(next: Bool) async throws -> [APIFixture] {
        let calendar = SportsDisplayDate.calendar
        let today = calendar.startOfDay(for: Date())
        let offsets = next ? Array(0...7) : Array(-7...0)
        var result: [APIFixture] = []
        for start in stride(from: 0, to: offsets.count, by: 3) {
            try Task.checkCancellation()
            let batch = Array(offsets[start..<min(start + 3, offsets.count)])
            let values = try await withThrowingTaskGroup(of: [APIFixture].self) { group in
                for offset in batch {
                    if let date = calendar.date(byAdding: .day, value: offset, to: today) {
                        group.addTask { try await self.fetch(date) }
                    }
                }
                var values: [APIFixture] = []
                for try await fixtures in group { values.append(contentsOf: fixtures) }
                return values
            }
            result.append(contentsOf: values)
        }
        return result
    }
}

@MainActor
final class APISportsStore: ObservableObject {
    static let shared = APISportsStore()
    @Published var today: [APIPlusMatch] = []
    @Published var loading = false
    @Published var error: String?
    @Published var lastUpdated: Date?
    private var refreshBusy = false
    private var refreshedDay: String?
    private init() {}

    private var seasonCandidates: [Int] {
        let current = APIFootballClient.currentSeason
        return current == 2024 ? [current] : [current, 2024]
    }

    func refreshToday(force: Bool = false) async {
        guard !refreshBusy, !Task.isCancelled else { return }
        let day = SharedFixtureDays.key(Date())
        if !force, refreshedDay == day, error == nil, let lastUpdated,
           (0..<AppRefreshPolicy.todayFreshness).contains(Date().timeIntervalSince(lastUpdated)) { return }
        refreshBusy = true; loading = true
        defer { refreshBusy = false; loading = false }
        do {
            let matches = try await fixtures(date: Date(), force: force)
            try Task.checkCancellation()
            today = matches; lastUpdated = Date(); refreshedDay = day; error = nil
        } catch {
            if !Task.isCancelled && !(error is CancellationError) { self.error = error.localizedDescription }
        }
    }
    func fixtures(date: Date, force: Bool = false) async throws -> [APIPlusMatch] {
        let fixtures = try await SharedFixtureDays.shared.fetch(date, force: force)
        try Task.checkCancellation()
        return fixtures.map(mapMatch).sorted { a, b in
            let pa = priority(a), pb = priority(b)
            if pa != pb { return pa > pb }
            if a.date != b.date { return (a.date ?? .distantFuture) < (b.date ?? .distantFuture) }
            return a.id < b.id
        }
    }
    func liveFixtures() async throws -> [APIPlusMatch] {
        try await fixtures(date: Date()).filter { isLive($0.status) }
    }
    func leagueFixtures(leagueID: String, count: Int = 20) async throws -> [APIPlusMatch] {
        async let recent = SharedFixtureDays.shared.window(next: false)
        async let upcoming = SharedFixtureDays.shared.window(next: true)
        let (past, future) = try await (recent, upcoming)
        var seen = Set<String>()
        let matches = (past + future).filter { $0.league.id.map(String.init) == leagueID }.map(mapMatch)
        return matches.filter { seen.insert($0.id).inserted }.sorted { a, b in
            let phaseA = FixturePhase.isFinished(a.status) ? 1 : 0
            let phaseB = FixturePhase.isFinished(b.status) ? 1 : 0
            if phaseA != phaseB { return phaseA < phaseB }
            return phaseA == 0 ? (a.date ?? .distantFuture) < (b.date ?? .distantFuture) : (a.date ?? .distantPast) > (b.date ?? .distantPast)
        }
    }
    func standings(leagueID: String) async throws -> [APIPlusStanding] {
        let envelope: APIEnvelope<[APIStandingLeague]> = try await APIFootballClient.get("standings", query: [
            .init(name: "league", value: leagueID), .init(name: "season", value: String(APIFootballClient.currentSeason))
        ])
        let rows = envelope.response.first?.league.standings?.flatMap { $0 } ?? []
        return rows.compactMap { r in
            guard let teamID = r.team.id, let rank = r.rank, let points = r.points, let played = r.all?.played else { return nil }
            return APIPlusStanding(id: "\(leagueID)-\(teamID)", rank: rank, teamID: String(teamID), team: r.team.name ?? "—", logo: r.team.logo,
                played: played, win: r.all?.win ?? 0, draw: r.all?.draw ?? 0, lose: r.all?.lose ?? 0,
                goalsFor: r.all?.goals?.for ?? 0, goalsAgainst: r.all?.goals?.against ?? 0, goalDifference: r.goalsDiff ?? 0, points: points, form: r.form)
        }.sorted { $0.rank < $1.rank }
    }

    func topScorers(leagueID: String) async throws -> [APIPlusScorer] {
        var lastError: Error?
        for season in seasonCandidates {
            do {
                let envelope: APIEnvelope<[APITopScorerItem]> = try await APIFootballClient.get("players/topscorers", query: [
                    .init(name: "league", value: leagueID), .init(name: "season", value: String(season))
                ])
                guard !envelope.response.isEmpty else { continue }
                return envelope.response.enumerated().map { index, item in
                    let stat = item.statistics.first
                    return APIPlusScorer(id: "\(leagueID)-\(season)-\(item.player.id)", season: season, rank: index + 1,
                        playerID: String(item.player.id), name: item.player.name ?? "—", photo: item.player.photo,
                        nationality: item.player.nationality, teamID: stat?.team.id.map(String.init), team: stat?.team.name ?? "—",
                        teamLogo: stat?.team.logo, appearances: stat?.games?.appearances ?? 0, minutes: stat?.games?.minutes ?? 0,
                        goals: stat?.goals?.total ?? 0, assists: stat?.goals?.assists ?? 0)
                }
            } catch {
                if error is CancellationError { throw error }
                lastError = error
            }
        }
        if let lastError { throw lastError }
        return []
    }

    func playerSeasonStats(playerID: String) async throws -> [APIPlusPlayerSeasonStat] {
        var lastError: Error?
        for season in seasonCandidates {
            do {
                let envelope: APIEnvelope<[APITopScorerItem]> = try await APIFootballClient.get("players", query: [
                    .init(name: "id", value: playerID), .init(name: "season", value: String(season))
                ])
                guard let item = envelope.response.first(where: { String($0.player.id) == playerID }), !item.statistics.isEmpty else { continue }
                return item.statistics.enumerated().map { index, stat in
                    APIPlusPlayerSeasonStat(playerID: playerID, season: season, index: index, statistic: stat)
                }
            } catch {
                if error is CancellationError { throw error }
                lastError = error
            }
        }
        if let lastError { throw lastError }
        return []
    }

    func searchTeams(_ text: String) async throws -> [APIPlusTeam] {
        var query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.lowercased().hasPrefix("al ") || query.lowercased().hasPrefix("al-") { query = String(query.dropFirst(3)) }
        let envelope: APIEnvelope<[APITeamSearchItem]> = try await APIFootballClient.get("teams", query: [.init(name: "search", value: query)])
        return envelope.response.map { item in
            APIPlusTeam(id: String(item.team.id), name: item.team.name ?? "—", country: item.team.country,
                        founded: item.team.founded, logo: item.team.logo, venue: item.venue?.name, city: item.venue?.city, venueImage: item.venue?.image)
        }.sorted { left, right in
            let sa = left.country == "Saudi-Arabia", sb = right.country == "Saudi-Arabia"
            if sa != sb { return sa }
            let a = left.name.hasSuffix(" W") || left.name.contains(" U"), b = right.name.hasSuffix(" W") || right.name.contains(" U")
            if a != b { return !a }
            return left.name == right.name ? left.id < right.id : left.name < right.name
        }
    }
    func team(id: String) async throws -> APIPlusTeam? {
        let envelope: APIEnvelope<[APITeamSearchItem]> = try await APIFootballClient.get("teams", query: [.init(name: "id", value: id)])
        guard let item = envelope.response.first(where: { String($0.team.id) == id }) else { return nil }
        return APIPlusTeam(id: String(item.team.id), name: item.team.name ?? "—", country: item.team.country,
                          founded: item.team.founded, logo: item.team.logo, venue: item.venue?.name, city: item.venue?.city, venueImage: item.venue?.image)
    }
    func searchPlayers(_ text: String) async throws -> [APIPlusPlayer] {
        let envelope: APIEnvelope<[APIPlayerProfileItem]> = try await APIFootballClient.get("players/profiles", query: [.init(name: "search", value: text)])
        return envelope.response.map(mapPlayer)
    }
    func player(id: String) async throws -> APIPlusPlayer? {
        let envelope: APIEnvelope<[APIPlayerProfileItem]> = try await APIFootballClient.get("players/profiles", query: [.init(name: "player", value: id)])
        return envelope.response.first(where: { String($0.player.id) == id }).map(mapPlayer)
    }
    func teamFixtures(teamID: String, next: Bool) async throws -> [APIPlusMatch] {
        let fixtures = try await SharedFixtureDays.shared.window(next: next)
        try Task.checkCancellation()
        return fixtures.filter { item in
            (item.teams.home.id.map(String.init) == teamID || item.teams.away.id.map(String.init) == teamID)
        }.map(mapMatch).filter { match in
            next ? (FixturePhase.isUpcoming(match.status) || isLive(match.status)) : FixturePhase.isFinished(match.status)
        }.sorted { a, b in
            next ? (a.date ?? .distantFuture) < (b.date ?? .distantFuture) : (a.date ?? .distantPast) > (b.date ?? .distantPast)
        }
    }
    private func mapPlayer(_ item: APIPlayerProfileItem) -> APIPlusPlayer {
        let p = item.player
        return APIPlusPlayer(id: String(p.id), name: p.name ?? "—", nationality: p.nationality,
                             birth: p.birth?.date, height: p.height, weight: p.weight, photo: p.photo)
    }
    private func mapMatch(_ item: APIFixture) -> APIPlusMatch {
        APIPlusMatch(id: String(item.fixture.id), leagueID: item.league.id.map(String.init),
            league: item.league.name ?? "كرة القدم", leagueLogo: item.league.logo,
            homeID: item.teams.home.id.map(String.init), home: item.teams.home.name ?? "—", homeLogo: item.teams.home.logo,
            awayID: item.teams.away.id.map(String.init), away: item.teams.away.name ?? "—", awayLogo: item.teams.away.logo,
            homeScore: item.goals.home, awayScore: item.goals.away,
            date: item.fixture.date.flatMap { ISO8601DateFormatter().date(from: $0) },
            status: item.fixture.status.short ?? item.fixture.status.long ?? "", elapsed: item.fixture.status.elapsed)
    }
    private func priority(_ match: APIPlusMatch) -> Int {
        let important = ["307", "2", "39", "140", "135", "78", "61", "17"]
        return (important.contains(match.leagueID ?? "") ? 200 : 0) + (isLive(match.status) ? 100 : 0)
    }
    func isLive(_ status: String) -> Bool { MatchLivePolicy.isLive(status) }
}
