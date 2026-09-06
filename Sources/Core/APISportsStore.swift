import Foundation

struct APIPlusMatch: Identifiable, Hashable {
    let id: String
    let leagueID: String?
    let league: String
    let leagueLogo: String?
    let homeID: String?
    let home: String
    let homeLogo: String?
    let awayID: String?
    let away: String
    let awayLogo: String?
    let homeScore: Int?
    let awayScore: Int?
    let date: Date?
    let status: String
    let elapsed: Int?
}

struct APIPlusTeam: Identifiable, Hashable {
    let id: String
    let name: String
    let country: String?
    let founded: Int?
    let logo: String?
    let venue: String?
    let city: String?
    let venueImage: String?
}

struct APIPlusPlayer: Identifiable, Hashable {
    let id: String
    let name: String
    let nationality: String?
    let birth: String?
    let height: String?
    let weight: String?
    let photo: String?
}

struct APIPlusStanding: Identifiable, Hashable {
    let id: String
    let rank: Int
    let teamID: String
    let team: String
    let logo: String?
    let played: Int
    let win: Int
    let draw: Int
    let lose: Int
    let goalsFor: Int
    let goalsAgainst: Int
    let goalDifference: Int
    let points: Int
    let form: String?
}

struct APIPlusScorer: Identifiable, Hashable {
    let id: String
    let rank: Int
    let playerID: String
    let name: String
    let photo: String?
    let nationality: String?
    let teamID: String?
    let team: String
    let teamLogo: String?
    let appearances: Int
    let minutes: Int
    let goals: Int
    let assists: Int
}

@MainActor
final class APISportsStore: ObservableObject {
    static let shared = APISportsStore()
    @Published var today: [APIPlusMatch] = []
    @Published var loading = false
    @Published var error: String?
    @Published var lastUpdated: Date?

    private init() {}

    func refreshToday(force: Bool = false) async {
        if !force, let lastUpdated, Date().timeIntervalSince(lastUpdated) < 45, !today.isEmpty { return }
        loading = today.isEmpty
        defer { loading = false }
        do {
            today = try await fixtures(date: Date())
            lastUpdated = Date()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func fixtures(date: Date) async throws -> [APIPlusMatch] {
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "yyyy-MM-dd"
        let envelope: APIEnvelope<[APIFixture]> = try await APIFootballClient.get("fixtures", query: [
            .init(name: "date", value: df.string(from: date)),
            .init(name: "timezone", value: "Asia/Riyadh")
        ])
        return envelope.response.map(mapMatch).sorted { priority($0) > priority($1) }
    }

    func liveFixtures() async throws -> [APIPlusMatch] {
        let envelope: APIEnvelope<[APIFixture]> = try await APIFootballClient.get("fixtures", query: [.init(name: "live", value: "all")])
        return envelope.response.map(mapMatch).sorted { priority($0) > priority($1) }
    }

    func leagueFixtures(leagueID: String, count: Int = 20) async throws -> [APIPlusMatch] {
        let season = String(APIFootballClient.currentSeason)
        async let recentEnvelope: APIEnvelope<[APIFixture]> = APIFootballClient.get("fixtures", query: [
            .init(name: "league", value: leagueID),
            .init(name: "season", value: season),
            .init(name: "last", value: String(max(5, count / 2))),
            .init(name: "timezone", value: "Asia/Riyadh")
        ])
        async let nextEnvelope: APIEnvelope<[APIFixture]> = APIFootballClient.get("fixtures", query: [
            .init(name: "league", value: leagueID),
            .init(name: "season", value: season),
            .init(name: "next", value: String(max(5, count / 2))),
            .init(name: "timezone", value: "Asia/Riyadh")
        ])
        let (recent, upcoming) = try await (recentEnvelope, nextEnvelope)
        let combined = recent.response + upcoming.response
        var seen = Set<String>()
        return combined.map(mapMatch).filter { seen.insert($0.id).inserted }.sorted {
            ($0.date ?? .distantPast) > ($1.date ?? .distantPast)
        }
    }

    func standings(leagueID: String) async throws -> [APIPlusStanding] {
        let envelope: APIEnvelope<[APIStandingLeague]> = try await APIFootballClient.get("standings", query: [
            .init(name: "league", value: leagueID),
            .init(name: "season", value: String(APIFootballClient.currentSeason))
        ])
        let rows = envelope.response.first?.league.standings?.flatMap { $0 } ?? []
        return rows.map { r in
            APIPlusStanding(id: "\(leagueID)-\(r.team.id ?? 0)", rank: r.rank ?? 0,
                            teamID: String(r.team.id ?? 0), team: r.team.name ?? "—", logo: r.team.logo,
                            played: r.all?.played ?? 0, win: r.all?.win ?? 0, draw: r.all?.draw ?? 0,
                            lose: r.all?.lose ?? 0, goalsFor: r.all?.goals?.for ?? 0,
                            goalsAgainst: r.all?.goals?.against ?? 0, goalDifference: r.goalsDiff ?? 0,
                            points: r.points ?? 0, form: r.form)
        }.sorted { $0.rank < $1.rank }
    }

    func topScorers(leagueID: String) async throws -> [APIPlusScorer] {
        let envelope: APIEnvelope<[APITopScorerItem]> = try await APIFootballClient.get("players/topscorers", query: [
            .init(name: "league", value: leagueID),
            .init(name: "season", value: String(APIFootballClient.currentSeason))
        ])
        return envelope.response.enumerated().map { index, item in
            let stat = item.statistics.first
            return APIPlusScorer(
                id: "\(leagueID)-\(item.player.id)",
                rank: index + 1,
                playerID: String(item.player.id),
                name: item.player.name ?? "—",
                photo: item.player.photo,
                nationality: item.player.nationality,
                teamID: stat?.team.id.map(String.init),
                team: stat?.team.name ?? "—",
                teamLogo: stat?.team.logo,
                appearances: stat?.games?.appearances ?? 0,
                minutes: stat?.games?.minutes ?? 0,
                goals: stat?.goals?.total ?? 0,
                assists: stat?.goals?.assists ?? 0
            )
        }
    }

    func searchTeams(_ text: String) async throws -> [APIPlusTeam] {
        let envelope: APIEnvelope<[APITeamSearchItem]> = try await APIFootballClient.get("teams", query: [.init(name: "search", value: text)])
        return envelope.response.map { item in
            APIPlusTeam(id: String(item.team.id), name: item.team.name ?? "—", country: item.team.country,
                        founded: item.team.founded, logo: item.team.logo, venue: item.venue?.name,
                        city: item.venue?.city, venueImage: item.venue?.image)
        }
    }

    func team(id: String) async throws -> APIPlusTeam? {
        let envelope: APIEnvelope<[APITeamSearchItem]> = try await APIFootballClient.get("teams", query: [.init(name: "id", value: id)])
        guard let item = envelope.response.first else { return nil }
        return APIPlusTeam(id: String(item.team.id), name: item.team.name ?? "—", country: item.team.country,
                           founded: item.team.founded, logo: item.team.logo, venue: item.venue?.name,
                           city: item.venue?.city, venueImage: item.venue?.image)
    }

    func searchPlayers(_ text: String) async throws -> [APIPlusPlayer] {
        let envelope: APIEnvelope<[APIPlayerProfileItem]> = try await APIFootballClient.get("players/profiles", query: [.init(name: "search", value: text)])
        return envelope.response.map(mapPlayer)
    }

    func player(id: String) async throws -> APIPlusPlayer? {
        let envelope: APIEnvelope<[APIPlayerProfileItem]> = try await APIFootballClient.get("players/profiles", query: [.init(name: "player", value: id)])
        return envelope.response.first.map(mapPlayer)
    }

    func teamFixtures(teamID: String, next: Bool) async throws -> [APIPlusMatch] {
        let envelope: APIEnvelope<[APIFixture]> = try await APIFootballClient.get("fixtures", query: [
            .init(name: "team", value: teamID), .init(name: next ? "next" : "last", value: "10")
        ])
        return envelope.response.map(mapMatch)
    }

    private func mapPlayer(_ item: APIPlayerProfileItem) -> APIPlusPlayer {
        let p = item.player
        return APIPlusPlayer(id: String(p.id), name: p.name ?? "—", nationality: p.nationality,
                             birth: p.birth?.date, height: p.height, weight: p.weight, photo: p.photo)
    }

    private func mapMatch(_ item: APIFixture) -> APIPlusMatch {
        let date = item.fixture.date.flatMap { ISO8601DateFormatter().date(from: $0) }
        return APIPlusMatch(id: String(item.fixture.id), leagueID: item.league.id.map(String.init),
                            league: item.league.name ?? "كرة القدم", leagueLogo: item.league.logo,
                            homeID: item.teams.home.id.map(String.init), home: item.teams.home.name ?? "—", homeLogo: item.teams.home.logo,
                            awayID: item.teams.away.id.map(String.init), away: item.teams.away.name ?? "—", awayLogo: item.teams.away.logo,
                            homeScore: item.goals.home, awayScore: item.goals.away, date: date,
                            status: item.fixture.status.short ?? item.fixture.status.long ?? "", elapsed: item.fixture.status.elapsed)
    }

    private func priority(_ m: APIPlusMatch) -> Int {
        let name = m.league.lowercased(); var p = 0
        if name.contains("saudi") { p += 50 }
        if name.contains("champions") { p += 45 }
        if name.contains("premier") || name.contains("la liga") || name.contains("serie a") || name.contains("bundesliga") || name.contains("ligue 1") { p += 35 }
        if isLive(m.status) { p += 100 }
        return p
    }

    func isLive(_ status: String) -> Bool {
        ["1H","HT","2H","ET","BT","P","LIVE","INT"].contains(status.uppercased())
    }
}
