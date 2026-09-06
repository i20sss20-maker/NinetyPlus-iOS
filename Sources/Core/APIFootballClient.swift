import Foundation

enum APIFootballError: LocalizedError {
    case missingKey
    case badResponse

    var errorDescription: String? {
        switch self {
        case .missingKey: return "مفتاح API-Football غير مضاف"
        case .badResponse: return "تعذر قراءة استجابة API-Football"
        }
    }
}

enum APIFootballClient {
    private static let baseURL = URL(string: "https://v3.football.api-sports.io")!
    static let keyDefaultsName = "apiFootballKey"

    static var currentSeason: Int {
        let comps = Calendar.current.dateComponents([.year, .month], from: Date())
        let year = comps.year ?? 2026
        let month = comps.month ?? 8
        return month >= 7 ? year : year - 1
    }

    static var hasKey: Bool {
        !(UserDefaults.standard.string(forKey: keyDefaultsName) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        let key = (UserDefaults.standard.string(forKey: keyDefaultsName) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw APIFootballError.missingKey }

        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 18
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(key, forHTTPHeaderField: "x-apisports-key")
        request.setValue("NinetyPlus/1.1 iOS", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIFootballError.badResponse
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

struct APIEnvelope<T: Decodable>: Decodable { let response: T }

struct APIFixture: Decodable {
    struct Fixture: Decodable {
        struct Status: Decodable { let long: String?; let short: String?; let elapsed: Int? }
        let id: Int
        let date: String?
        let status: Status
    }
    struct League: Decodable { let id: Int?; let name: String?; let country: String?; let logo: String? }
    struct Team: Decodable { let id: Int?; let name: String?; let logo: String? }
    struct Teams: Decodable { let home: Team; let away: Team }
    struct Goals: Decodable { let home: Int?; let away: Int? }
    let fixture: Fixture
    let league: League
    let teams: Teams
    let goals: Goals
}

struct APIStandingLeague: Decodable {
    struct League: Decodable { let id: Int?; let name: String?; let standings: [[APIStanding]]? }
    let league: League
}

struct APIStanding: Decodable {
    struct Team: Decodable { let id: Int?; let name: String?; let logo: String? }
    struct Goals: Decodable { let `for`: Int?; let against: Int? }
    struct All: Decodable { let played: Int?; let win: Int?; let draw: Int?; let lose: Int?; let goals: Goals? }
    let rank: Int?
    let team: Team
    let points: Int?
    let goalsDiff: Int?
    let form: String?
    let all: All?
}

struct APITeamSearchItem: Decodable {
    struct Team: Decodable { let id: Int; let name: String?; let country: String?; let founded: Int?; let logo: String? }
    struct Venue: Decodable { let name: String?; let city: String?; let image: String? }
    let team: Team
    let venue: Venue?
}

struct APIPlayerProfileItem: Decodable {
    struct Player: Decodable {
        struct Birth: Decodable { let date: String?; let place: String?; let country: String? }
        let id: Int
        let name: String?
        let firstname: String?
        let lastname: String?
        let age: Int?
        let birth: Birth?
        let nationality: String?
        let height: String?
        let weight: String?
        let photo: String?
    }
    let player: Player
}

struct APITopScorerItem: Decodable {
    struct Player: Decodable {
        let id: Int
        let name: String?
        let photo: String?
        let nationality: String?
    }
    struct Statistic: Decodable {
        struct Team: Decodable { let id: Int?; let name: String?; let logo: String? }
        struct League: Decodable { let id: Int?; let name: String?; let country: String?; let logo: String? }
        struct Games: Decodable { let appearances: Int?; let minutes: Int?; let position: String?; let rating: String? }
        struct Goals: Decodable { let total: Int?; let assists: Int? }
        struct Cards: Decodable { let yellow: Int?; let red: Int? }
        let team: Team
        let league: League?
        let games: Games?
        let goals: Goals?
        let cards: Cards?
    }
    let player: Player
    let statistics: [Statistic]
}

struct APIEventItem: Decodable {
    struct Time: Decodable { let elapsed: Int?; let extra: Int? }
    struct Team: Decodable { let id: Int?; let name: String?; let logo: String? }
    struct Player: Decodable { let id: Int?; let name: String? }
    struct Assist: Decodable { let id: Int?; let name: String? }
    let time: Time
    let team: Team
    let player: Player
    let assist: Assist
    let type: String?
    let detail: String?
    let comments: String?
}

struct APIStatisticTeam: Decodable {
    struct Team: Decodable { let id: Int?; let name: String?; let logo: String? }
    struct Stat: Decodable { let type: String?; let value: APIStatValue? }
    let team: Team
    let statistics: [Stat]
}

enum APIStatValue: Decodable {
    case string(String), int(Int), double(Double), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Int.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else { self = .string((try? c.decode(String.self)) ?? "") }
    }
    var text: String {
        switch self {
        case .string(let v): return v
        case .int(let v): return String(v)
        case .double(let v): return String(v)
        case .null: return "0"
        }
    }
}

struct APILineupItem: Decodable {
    struct Team: Decodable { let id: Int?; let name: String?; let logo: String? }
    struct Coach: Decodable { let id: Int?; let name: String?; let photo: String? }
    struct Slot: Decodable {
        struct Player: Decodable { let id: Int?; let name: String?; let number: Int?; let pos: String?; let grid: String? }
        let player: Player
    }
    let team: Team
    let coach: Coach?
    let formation: String?
    let startXI: [Slot]?
    let substitutes: [Slot]?
}
