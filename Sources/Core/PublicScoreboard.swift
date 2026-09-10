import Foundation

/// Keyless public fallback for fixture lists. API-Football remains the primary
/// provider; this source is used only when that service is rate-limited or
/// temporarily unavailable. ESPN IDs stay namespaced and are never sent to
/// API-Football endpoints.
enum PublicScoreboardSource {
    struct League: Hashable {
        let apiFootballID: String
        let espnCode: String
        let name: String
        let logo: String?
    }

    static let leagues: [League] = [
        .init(apiFootballID: "307", espnCode: "ksa.1", name: "Saudi Pro League", logo: "https://media.api-sports.io/football/leagues/307.png"),
        .init(apiFootballID: "39", espnCode: "eng.1", name: "Premier League", logo: "https://media.api-sports.io/football/leagues/39.png"),
        .init(apiFootballID: "140", espnCode: "esp.1", name: "La Liga", logo: "https://media.api-sports.io/football/leagues/140.png"),
        .init(apiFootballID: "78", espnCode: "ger.1", name: "Bundesliga", logo: "https://media.api-sports.io/football/leagues/78.png"),
        .init(apiFootballID: "135", espnCode: "ita.1", name: "Serie A", logo: "https://media.api-sports.io/football/leagues/135.png"),
        .init(apiFootballID: "61", espnCode: "fra.1", name: "Ligue 1", logo: "https://media.api-sports.io/football/leagues/61.png"),
        .init(apiFootballID: "2", espnCode: "uefa.champions", name: "UEFA Champions League", logo: "https://media.api-sports.io/football/leagues/2.png")
    ]

    private struct Scoreboard: Decodable { let events: [Event] }
    private struct Event: Decodable {
        let id: String
        let date: String?
        let status: Status?
        let competitions: [Competition]
    }
    private struct Status: Decodable {
        let type: StatusType?
        let period: Int?
        let displayClock: String?
    }
    private struct StatusType: Decodable {
        let state: String?
        let completed: Bool?
        let description: String?
        let detail: String?
        let name: String?
    }
    private struct Competition: Decodable {
        let competitors: [Competitor]
        let status: Status?
    }
    private struct Competitor: Decodable {
        let id: String?
        let homeAway: String?
        let score: String?
        let team: Team
        enum CodingKeys: String, CodingKey { case id, homeAway, score, team }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(String.self, forKey: .id)
            homeAway = try c.decodeIfPresent(String.self, forKey: .homeAway)
            team = try c.decode(Team.self, forKey: .team)
            struct Score: Decodable { let displayValue: String?; let value: Double? }
            if let text = try? c.decode(String.self, forKey: .score) { score = text }
            else if let value = try? c.decode(Score.self, forKey: .score) { score = value.displayValue ?? value.value.map { String(Int($0)) } }
            else { score = nil }
        }
    }
    private struct Team: Decodable {
        let id: String?
        let displayName: String?
        let shortDisplayName: String?
        let logo: String?
    }

    actor Cache {
        static let shared = Cache()
        struct Entry { let date: Date; let value: [APIPlusMatch] }
        var values: [String: Entry] = [:]
        var pending: [String: Task<[APIPlusMatch], Error>] = [:]

        func load(date: Date, league: League, force: Bool) async throws -> [APIPlusMatch] {
            let key = "\(league.espnCode):\(dayKey(date))"
            let ttl: TimeInterval = SportsDisplayDate.calendar.isDateInToday(date) ? 60 : 1800
            if !force, let cached = values[key], (0..<ttl).contains(Date().timeIntervalSince(cached.date)) { return cached.value }
            if let task = pending[key] { return try await task.value }
            let task = Task { try await fetchRemote(date: date, league: league) }
            pending[key] = task
            defer { pending[key] = nil }
            let result = try await task.value
            if values.count > 96, values[key] == nil, let oldest = values.min(by: { $0.value.date < $1.value.date })?.key { values[oldest] = nil }
            values[key] = Entry(date: Date(), value: result)
            return result
        }
    }

    static func fixtures(date: Date, force: Bool = false) async throws -> [APIPlusMatch] {
        try await withThrowingTaskGroup(of: [APIPlusMatch].self) { group in
            for league in leagues {
                group.addTask { try await Cache.shared.load(date: date, league: league, force: force) }
            }
            var all: [APIPlusMatch] = []
            var successfulLeagues = 0
            // A single public league failure should not discard successful leagues,
            // and a successful empty match day is a real empty state, not an outage.
            while let result = await group.nextResult() {
                if case .success(let matches) = result {
                    successfulLeagues += 1
                    all.append(contentsOf: matches)
                }
            }
            guard successfulLeagues > 0 else { throw APIFootballError.serviceUnavailable }
            return deduplicated(all)
        }
    }

    static func leagueWindow(leagueID: String, next: Bool) async throws -> [APIPlusMatch] {
        guard let league = leagues.first(where: { $0.apiFootballID == leagueID }) else { return [] }
        let calendar = SportsDisplayDate.calendar
        let today = calendar.startOfDay(for: Date())
        let offsets = next ? Array(0...7) : Array(-7...0)
        var output: [APIPlusMatch] = []
        var successfulDays = 0
        for start in stride(from: 0, to: offsets.count, by: 3) {
            let batch = Array(offsets[start..<min(start + 3, offsets.count)])
            await withTaskGroup(of: Result<[APIPlusMatch], Error>.self) { group in
                for offset in batch {
                    guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
                    group.addTask {
                        do { return .success(try await Cache.shared.load(date: date, league: league, force: false)) }
                        catch { return .failure(error) }
                    }
                }
                for await result in group {
                    if case .success(let value) = result { successfulDays += 1; output.append(contentsOf: value) }
                }
            }
        }
        guard successfulDays > 0 else { throw APIFootballError.serviceUnavailable }
        return deduplicated(output)
    }

    static func teamWindow(teamName: String, next: Bool) async throws -> [APIPlusMatch] {
        let needle = normalizedTeam(teamName)
        guard !needle.isEmpty else { return [] }
        let calendar = SportsDisplayDate.calendar
        let today = calendar.startOfDay(for: Date())
        let offsets = next ? Array(0...7) : Array(-7...0)
        var output: [APIPlusMatch] = []
        var successfulDays = 0
        for offset in offsets {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            do {
                let matches = try await fixtures(date: date)
                successfulDays += 1
                output.append(contentsOf: matches.filter {
                    normalizedTeam($0.home) == needle || normalizedTeam($0.away) == needle ||
                    normalizedTeam(SportsArabic.team($0.home)) == needle || normalizedTeam(SportsArabic.team($0.away)) == needle
                })
            } catch { continue }
        }
        guard successfulDays > 0 else { throw APIFootballError.serviceUnavailable }
        return deduplicated(output)
    }

    static func isFallbackID(_ id: String) -> Bool { id.hasPrefix("espn:") }

    static func teamSchedule(id: String, next: Bool) async throws -> [APIPlusMatch] {
        let parts = id.split(separator: ":").map(String.init)
        guard parts.count == 4, parts[0] == "espn", parts[2] == "team",
              let league = leagues.first(where: { $0.espnCode == parts[1] }),
              parts[3].allSatisfy({ $0.isASCII && $0.isNumber }) else { throw FreeCoverageError.unavailable }
        let url = URL(string: "https://site.web.api.espn.com/apis/site/v2/sports/soccer/\(league.espnCode)/teams/\(parts[3])/schedule")!
        let data = try await FreeDataCache.shared.data(url: url, lifetime: 120, staleLifetime: 120)
        let schedule = try JSONDecoder().decode(Scoreboard.self, from: data)
        let today = SportsDisplayDate.calendar.startOfDay(for: Date())
        let start = today.addingTimeInterval(next ? 0 : -7 * 86400)
        let end = today.addingTimeInterval(next ? 8 * 86400 : 86400)
        return deduplicated(schedule.events.compactMap { map($0, league: league) }.filter {
            guard let date = $0.date else { return false }
            return start <= date && date < end && (next ? !FixturePhase.isFinished($0.status) : FixturePhase.isFinished($0.status))
        })
    }

    private static func fetchRemote(date: Date, league: League) async throws -> [APIPlusMatch] {
        var components = URLComponents(string: "https://site.web.api.espn.com/apis/site/v2/sports/soccer/\(league.espnCode)/scoreboard")!
        components.queryItems = [URLQueryItem(name: "dates", value: dayKey(date).replacingOccurrences(of: "-", with: ""))]
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .useProtocolCachePolicy
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw APIFootballError.serviceUnavailable }
        let decoded = try JSONDecoder().decode(Scoreboard.self, from: data)
        return decoded.events.compactMap { map($0, league: league) }.filter {
            $0.date.map { SportsDisplayDate.calendar.isDate($0, inSameDayAs: date) } ?? false
        }
    }

    private static func map(_ event: Event, league: League) -> APIPlusMatch? {
        guard let competition = event.competitions.first else { return nil }
        guard let home = competition.competitors.first(where: { $0.homeAway?.lowercased() == "home" }),
              let away = competition.competitors.first(where: { $0.homeAway?.lowercased() == "away" }) else { return nil }
        let status = competition.status ?? event.status
        let state = status?.type?.state?.lowercased() ?? ""
        let completed = status?.type?.completed == true
        let shortStatus = mappedStatus(state: state, completed: completed, description: status?.type?.description, detail: status?.type?.detail, name: status?.type?.name)
        let started = shortStatus != "NS" && shortStatus != "TBD" && shortStatus != "PST" && shortStatus != "CANC"
        return APIPlusMatch(
            id: "espn:\(league.espnCode):\(event.id)", leagueID: league.apiFootballID, league: league.name, leagueLogo: league.logo,
            homeID: home.id.map { "espn:\(league.espnCode):team:\($0)" }, home: home.team.displayName ?? home.team.shortDisplayName ?? "—", homeLogo: home.team.logo,
            awayID: away.id.map { "espn:\(league.espnCode):team:\($0)" }, away: away.team.displayName ?? away.team.shortDisplayName ?? "—", awayLogo: away.team.logo,
            homeScore: started ? Int(home.score ?? "") : nil, awayScore: started ? Int(away.score ?? "") : nil,
            date: event.date.flatMap(parseDate), status: shortStatus, elapsed: elapsed(status)
        )
    }

    static func mappedStatus(state: String, completed: Bool, description: String?, detail: String?, name: String?) -> String {
        let text = [description, detail, name].compactMap { $0 }.joined(separator: " ").lowercased()
        if text.contains("postpon") { return "PST" }
        if text.contains("cancel") { return "CANC" }
        if text.contains("suspend") { return "SUSP" }
        if text.contains("half") && !completed { return "HT" }
        if completed || state == "post" { return "FT" }
        if state == "in" { return "LIVE" }
        if state == "pre" { return "NS" }
        return "TBD"
    }

    private static func elapsed(_ status: Status?) -> Int? {
        guard status?.type?.state?.lowercased() == "in" else { return nil }
        if let clock = status?.displayClock {
            let digits = clock.prefix { $0.isNumber }
            if let value = Int(digits) { return value }
        }
        return nil
    }

    private static func parseDate(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mmX"
        return formatter.date(from: raw)
    }

    private static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = SportsDisplayDate.calendar
        formatter.timeZone = SportsDisplayDate.calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func normalizedTeam(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func deduplicated(_ values: [APIPlusMatch]) -> [APIPlusMatch] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.id).inserted }.sorted {
            if $0.date != $1.date { return ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
            return $0.id < $1.id
        }
    }
}
