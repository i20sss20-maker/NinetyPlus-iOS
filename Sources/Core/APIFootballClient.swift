import Foundation

enum APIFootballError: LocalizedError {
    case missingConfiguration
    case badResponse
    case serviceUnavailable
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .missingConfiguration: return "مصدر بيانات 90+ غير مهيأ"
        case .badResponse: return "تعذر قراءة استجابة مصدر بيانات 90+"
        case .serviceUnavailable: return "الخدمة غير متاحة مؤقتًا. حاول مرة أخرى بعد قليل"
        case .rateLimited: return "تم الوصول للحد المؤقت للطلبات. حاول مرة أخرى بعد قليل"
        }
    }
}

struct NinetyPlusBackendHealth: Decodable {
    let ok: Bool
    let service: String?
    let version: String?
    let platform: String?
    let providerConfigured: Bool?
    let cacheEntries: Int?
    let inFlightRequests: Int?
    let providerRequestsToday: Int?
    let providerDailyBudget: Int?
    let providerBudgetRemaining: Int?
    let providerRemoteBlocked: Bool?
    let time: String?

    var allowsDirectProviderRequests: Bool {
        guard ok, providerConfigured != false else { return false }
        if providerRemoteBlocked == true { return false }
        if let providerBudgetRemaining, providerBudgetRemaining <= 0 { return false }
        if let used = providerRequestsToday, let daily = providerDailyBudget, daily > 0, used >= daily { return false }
        return true
    }
}

private actor ProviderAvailabilityGate {
    private var allowed: Bool?
    private var checkedAt: Date?
    private let ttl: TimeInterval = 45

    func allowsRequests() async -> Bool {
        if let allowed, let checkedAt, Date().timeIntervalSince(checkedAt) < ttl { return allowed }
        do {
            let health = try await APIFootballClient.health()
            let result = health.allowsDirectProviderRequests
            allowed = result
            checkedAt = Date()
            return result
        } catch {
            // Health is an optimization, not a new single point of failure. If it
            // cannot be read, let the normal request path determine availability.
            allowed = nil
            checkedAt = nil
            return true
        }
    }

    func markBlocked() {
        allowed = false
        checkedAt = Date()
    }

    func invalidate() {
        allowed = nil
        checkedAt = nil
    }
}

enum APIFootballClient {
    static let backendURLDefaultsName = "ninetyPlusBackendURL"
    private static let providerGate = ProviderAvailabilityGate()

    static var currentSeason: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Riyadh") ?? .current
        let comps = calendar.dateComponents([.year, .month], from: Date())
        let year = comps.year ?? 2026
        let month = comps.month ?? 8
        return month >= 7 ? year : year - 1
    }

    static var backendURL: URL? {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "NINETYPLUS_BACKEND_URL") as? String,
           let url = normalizedBackendURL(configured) { return url }
        return normalizedBackendURL(UserDefaults.standard.string(forKey: backendURLDefaultsName) ?? "")
    }

    static var hasBackend: Bool { backendURL != nil }
    static var isConfigured: Bool { hasBackend }

    static func health() async throws -> NinetyPlusBackendHealth {
        guard let backendURL else { throw APIFootballError.missingConfiguration }
        let url = backendURL.appending(path: "api/health")
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("NinetyPlus/3.1 iOS", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await perform(request, retryOnce: true)
        return try JSONDecoder().decode(NinetyPlusBackendHealth.self, from: data)
    }

    static func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        guard let backendURL else { throw APIFootballError.missingConfiguration }
        guard await providerGate.allowsRequests() else { throw APIFootballError.rateLimited }

        var components = URLComponents(url: backendURL.appending(path: "api/football"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "path", value: path)] + query
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 18
        request.cachePolicy = .useProtocolCachePolicy
        request.setValue("NinetyPlus/3.1 iOS", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let data = try await perform(request, retryOnce: true)
            try Task.checkCancellation()
            try FootballResponseGuard.validate(data)
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw APIFootballError.badResponse
            }
        } catch APIFootballError.rateLimited {
            await providerGate.markBlocked()
            throw APIFootballError.rateLimited
        }
    }

    static func recheckProviderAvailability() async {
        await providerGate.invalidate()
    }

    private static func perform(_ request: URLRequest, retryOnce: Bool) async throws -> Data {
        try Task.checkCancellation()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw APIFootballError.badResponse }
            switch http.statusCode {
            case 200..<300:
                return data
            case 429:
                throw APIFootballError.rateLimited
            case 500..<600:
                if retryOnce {
                    try await Task.sleep(for: .milliseconds(650))
                    return try await perform(request, retryOnce: false)
                }
                throw APIFootballError.serviceUnavailable
            default:
                throw APIFootballError.badResponse
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as APIFootballError {
            throw error
        } catch let error as URLError {
            if error.code == .cancelled || Task.isCancelled { throw CancellationError() }
            let transient: Set<URLError.Code> = [.timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed]
            if retryOnce, transient.contains(error.code) {
                try await Task.sleep(for: .milliseconds(650))
                return try await perform(request, retryOnce: false)
            }
            throw APIFootballError.serviceUnavailable
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw APIFootballError.serviceUnavailable
        }
    }

    private static func normalizedBackendURL(_ raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
              components.host != nil else { return nil }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var url = components.url else { return nil }
        if !url.absoluteString.hasSuffix("/") { url.append(path: "") }
        return url
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
