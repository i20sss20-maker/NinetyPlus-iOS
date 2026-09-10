import Foundation

/// The public directory keeps its own IDs. They are never API-Football IDs.
enum FreeSportsDirectory {
    static let prefix = "tsdb:"
    struct Teams: Decodable { let teams: [Team]? }
    struct Players: Decodable { let player: [Player]?; let players: [Player]? }
    struct Team: Decodable {
        let idTeam: String; let strTeam: String; let strSport: String?
        let strCountry: String?; let intFormedYear: String?; let strBadge: String?
        let strStadium: String?; let strLocation: String?
        var value: APIPlusTeam {
            .init(id: prefix + idTeam, name: strTeam, country: strCountry,
                  founded: intFormedYear.flatMap(Int.init), logo: strBadge,
                  venue: strStadium, city: strLocation, venueImage: nil)
        }
    }
    struct Player: Decodable {
        let idPlayer: String; let strPlayer: String; let strSport: String?
        let strNationality: String?; let dateBorn: String?; let strHeight: String?
        let strWeight: String?; let strThumb: String?
        var value: APIPlusPlayer {
            .init(id: prefix + idPlayer, name: strPlayer, nationality: strNationality,
                  birth: dateBorn, height: strHeight, weight: strWeight, photo: strThumb)
        }
    }
    static func teams(_ query: String) async throws -> [APIPlusTeam] {
        // League catalogues include Saudi clubs that the free one-result search
        // can omit in favour of unrelated namesakes.
        let values = try await espnTeams()
        let key = normalized(query)
        return values.filter { normalized($0.name).contains(key) }
            .sorted { ($0.country == "Saudi Arabia" ? 0 : 1) < ($1.country == "Saudi Arabia" ? 0 : 1) }
    }
    static func players(_ query: String) async throws -> [APIPlusPlayer] {
        let query = ["Ronaldo": "Cristiano Ronaldo", "Messi": "Lionel Messi", "Neymar": "Neymar"] [query] ?? query
        let result: Players = try await get("searchplayers.php", key: "p", value: query)
        return (result.player ?? result.players ?? []).filter { $0.strSport == "Soccer" }.map(\.value)
    }
    static func team(_ id: String) async throws -> APIPlusTeam? {
        if id.hasPrefix("espn:") { return try await espnTeams().first(where: { $0.id == id }) }
        let result: Teams = try await get("lookupteam.php", key: "id", value: try identifier(id))
        return result.teams?.first(where: { prefix + $0.idTeam == id && $0.strSport == "Soccer" })?.value
    }
    static func player(_ id: String) async throws -> APIPlusPlayer? {
        let result: Players = try await get("lookupplayer.php", key: "id", value: try identifier(id))
        return (result.players ?? result.player)?.first(where: { prefix + $0.idPlayer == id && $0.strSport == "Soccer" })?.value
    }
    static func identifier(_ id: String) throws -> String {
        guard id.hasPrefix(prefix) else { throw APIFootballError.badResponse }
        let value = String(id.dropFirst(prefix.count))
        guard !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw APIFootballError.badResponse }
        return value
    }
    struct ESPNTeams: Decodable {
        struct Sport: Decodable { let leagues: [League] }
        struct League: Decodable { let teams: [Item] }
        struct Item: Decodable { let team: Team }
        struct Team: Decodable {
            struct Logo: Decodable { let href: String }
            let id: String; let displayName: String; let logos: [Logo]?
        }
        let sports: [Sport]
    }
    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "-", with: " ")
    }
    static func espnTeams() async throws -> [APIPlusTeam] {
        try await withThrowingTaskGroup(of: [APIPlusTeam].self) { group in
            for league in PublicScoreboardSource.leagues {
                group.addTask {
                    let url = URL(string: "https://site.web.api.espn.com/apis/site/v2/sports/soccer/\(league.espnCode)/teams?limit=200")!
                    let data = try await FreeDataCache.shared.data(url: url, lifetime: 86400, staleLifetime: 604800)
                    let result = try JSONDecoder().decode(ESPNTeams.self, from: data)
                    return result.sports.flatMap(\.leagues).flatMap(\.teams).map { item in
                        APIPlusTeam(id: "espn:\(league.espnCode):team:\(item.team.id)", name: item.team.displayName,
                            country: league.espnCode == "ksa.1" ? "Saudi Arabia" : nil, founded: nil,
                            logo: item.team.logos?.first?.href, venue: nil, city: nil, venueImage: nil)
                    }
                }
            }
            var result: [APIPlusTeam] = []; var successes = 0
            while let value = await group.nextResult() {
                if case .success(let teams) = value { result += teams; successes += 1 }
            }
            try Task.checkCancellation()
            guard successes > 0 else { throw APIFootballError.serviceUnavailable }
            var seen = Set<String>()
            return result.filter { seen.insert($0.id).inserted }
        }
    }
    private static func get<T: Decodable>(_ path: String, key: String, value: String) async throws -> T {
        var url = URLComponents(string: "https://www.thesportsdb.com/api/v1/json/123/" + path)!
        url.queryItems = [.init(name: key, value: value)]
        let data = try await FreeDataCache.shared.data(url: url.url!, lifetime: 3600, staleLifetime: 604800)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// Persist only successful JSON responses; errors never replace useful data.
actor FreeDataCache {
    static let shared = FreeDataCache()
    struct Entry: Codable { let data: Data; let date: Date }
    private var entries: [String: Entry]
    private var pending: [String: Task<Data, Error>] = [:]
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.data(forKey: "free.directory.cache.v1")
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }
    func data(url: URL, lifetime: TimeInterval, staleLifetime: TimeInterval) async throws -> Data {
        let key = url.absoluteString
        let old = entries[key]
        if let old, (0..<lifetime).contains(Date().timeIntervalSince(old.date)) { return old.data }
        if let task = pending[key] { return try await task.value }
        let task = Task<Data, Error> {
            var request = URLRequest(url: url); request.timeoutInterval = 12
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  data.count < 2_000_000, (try? JSONSerialization.jsonObject(with: data)) != nil else {
                throw APIFootballError.serviceUnavailable
            }
            return data
        }
        pending[key] = task
        defer { pending[key] = nil }
        do {
            let data = try await task.value
            entries[key] = Entry(data: data, date: Date())
            while entries.count > 40, let oldest = entries.min(by: { $0.value.date < $1.value.date })?.key { entries[oldest] = nil }
            if let encoded = try? JSONEncoder().encode(entries) { defaults.set(encoded, forKey: "free.directory.cache.v1") }
            return data
        } catch {
            if let old, (0..<staleLifetime).contains(Date().timeIntervalSince(old.date)) { return old.data }
            throw error
        }
    }
}
