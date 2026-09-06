import Foundation

struct StandingRow: Identifiable, Decodable, Hashable {
    var id: String { idStanding ?? idTeam ?? "\(rank)-\(team)" }
    let idStanding: String?
    let intRank: String?
    let idTeam: String?
    let strTeam: String?
    let strBadge: String?
    let intPlayed: String?
    let intWin: String?
    let intDraw: String?
    let intLoss: String?
    let intGoalsFor: String?
    let intGoalsAgainst: String?
    let intGoalDifference: String?
    let intPoints: String?
    let strForm: String?

    var rank: Int { Int(intRank ?? "") ?? 0 }
    var team: String { strTeam ?? "—" }
    var played: Int { Int(intPlayed ?? "") ?? 0 }
    var wins: Int { Int(intWin ?? "") ?? 0 }
    var draws: Int { Int(intDraw ?? "") ?? 0 }
    var losses: Int { Int(intLoss ?? "") ?? 0 }
    var points: Int { Int(intPoints ?? "") ?? 0 }
}

struct TeamProfile: Identifiable, Decodable, Hashable {
    var id: String { idTeam ?? UUID().uuidString }
    let idTeam: String?
    let strTeam: String?
    let strTeamAlternate: String?
    let intFormedYear: String?
    let strLeague: String?
    let strStadium: String?
    let strLocation: String?
    let strDescriptionEN: String?
    let strBadge: String?
    let strLogo: String?
    let strFanart1: String?
    let strWebsite: String?
}

struct TeamEvent: Identifiable, Decodable, Hashable {
    var id: String { idEvent ?? "\(dateEvent ?? "")-\(strEvent ?? UUID().uuidString)" }
    let idEvent: String?
    let strEvent: String?
    let strLeague: String?
    let strHomeTeam: String?
    let strAwayTeam: String?
    let intHomeScore: String?
    let intAwayScore: String?
    let dateEvent: String?
    let strTime: String?
    let strStatus: String?
    let strHomeTeamBadge: String?
    let strAwayTeamBadge: String?
}

struct MatchStat: Identifiable, Decodable, Hashable {
    var id: String { idStatistic ?? "\(name)-\(home)-\(away)" }
    let idStatistic: String?
    let strStat: String?
    let intHome: String?
    let intAway: String?
    var name: String { strStat ?? "إحصائية" }
    var home: String { intHome ?? "0" }
    var away: String { intAway ?? "0" }
}

struct TimelineEvent: Identifiable, Decodable, Hashable {
    var id: String { idTimeline ?? UUID().uuidString }
    let idTimeline: String?
    let strTimeline: String?
    let strTimelineDetail: String?
    let strHome: String?
    let strPlayer: String?
    let strAssist: String?
    let intTime: String?
    let strTeam: String?
    let strComment: String?
}

struct LineupPlayer: Identifiable, Decodable, Hashable {
    var id: String { idLineup ?? idPlayer ?? UUID().uuidString }
    let idLineup: String?
    let idPlayer: String?
    let strPosition: String?
    let strHome: String?
    let strSubstitute: String?
    let intSquadNumber: String?
    let strPlayer: String?
    let strTeam: String?
    let strCutout: String?
    let strThumb: String?
}

private struct TableResponse: Decodable { let table: [StandingRow]? }
private struct TeamResponse: Decodable { let teams: [TeamProfile]? }
private struct TeamEventsResponse: Decodable { let events: [TeamEvent]?; let results: [TeamEvent]? }
private struct StatsResponse: Decodable { let eventstats: [MatchStat]? }
private struct TimelineResponse: Decodable { let timeline: [TimelineEvent]? }
private struct LineupResponse: Decodable { let lineup: [LineupPlayer]? }

struct LeagueOption: Identifiable, Hashable {
    let id: String
    let arabicName: String
    let englishName: String

    static let featured: [LeagueOption] = [
        .init(id: "4668", arabicName: "الدوري السعودي", englishName: "Saudi-Arabian Pro League"),
        .init(id: "4328", arabicName: "الدوري الإنجليزي", englishName: "English Premier League"),
        .init(id: "4335", arabicName: "الدوري الإسباني", englishName: "Spanish La Liga"),
        .init(id: "4331", arabicName: "الدوري الألماني", englishName: "German Bundesliga"),
        .init(id: "4332", arabicName: "الدوري الإيطالي", englishName: "Italian Serie A"),
        .init(id: "4334", arabicName: "الدوري الفرنسي", englishName: "French Ligue 1")
    ]
}

enum FootballAPI {
    static let base = "https://www.thesportsdb.com/api/v1/json/123"

    static func table(leagueID: String) async throws -> [StandingRow] {
        let url = URL(string: "\(base)/lookuptable.php?l=\(leagueID)")!
        let response: TableResponse = try await get(url)
        return (response.table ?? []).sorted { $0.rank < $1.rank }
    }

    static func team(id: String) async throws -> TeamProfile? {
        let url = URL(string: "\(base)/lookupteam.php?id=\(id)")!
        let response: TeamResponse = try await get(url)
        return response.teams?.first
    }

    static func nextEvents(teamID: String) async throws -> [TeamEvent] {
        let url = URL(string: "\(base)/eventsnext.php?id=\(teamID)")!
        let response: TeamEventsResponse = try await get(url)
        return response.events ?? response.results ?? []
    }

    static func lastEvents(teamID: String) async throws -> [TeamEvent] {
        let url = URL(string: "\(base)/eventslast.php?id=\(teamID)")!
        let response: TeamEventsResponse = try await get(url)
        return response.results ?? response.events ?? []
    }

    static func stats(eventID: String) async throws -> [MatchStat] {
        let url = URL(string: "\(base)/lookupeventstats.php?id=\(eventID)")!
        let response: StatsResponse = try await get(url)
        return response.eventstats ?? []
    }

    static func timeline(eventID: String) async throws -> [TimelineEvent] {
        let url = URL(string: "\(base)/lookuptimeline.php?id=\(eventID)")!
        let response: TimelineResponse = try await get(url)
        return (response.timeline ?? []).sorted { (Int($0.intTime ?? "") ?? 0) < (Int($1.intTime ?? "") ?? 0) }
    }

    static func lineup(eventID: String) async throws -> [LineupPlayer] {
        let url = URL(string: "\(base)/lookuplineup.php?id=\(eventID)")!
        let response: LineupResponse = try await get(url)
        return response.lineup ?? []
    }

    private static func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("NinetyPlus/1.2 iOS", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

@MainActor
final class MatchInsightStore: ObservableObject {
    @Published var stats: [MatchStat] = []
    @Published var timeline: [TimelineEvent] = []
    @Published var lineup: [LineupPlayer] = []
    @Published var loading = false
    @Published var loaded = false

    func load(eventID: String) async {
        guard !loaded else { return }
        loading = true
        async let s = try? FootballAPI.stats(eventID: eventID)
        async let t = try? FootballAPI.timeline(eventID: eventID)
        async let l = try? FootballAPI.lineup(eventID: eventID)
        let values = await (s, t, l)
        stats = values.0 ?? []
        timeline = values.1 ?? []
        lineup = values.2 ?? []
        loading = false
        loaded = true
    }
}
