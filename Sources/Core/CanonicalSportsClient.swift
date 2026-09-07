import Foundation

enum CanonicalSportsClient {
    struct FixturesResponse: Decodable {
        let date: String
        let timezone: String
        let generatedAt: String?
        let matches: [Match]
        let meta: Meta?
        struct Meta: Decodable {
            let apiFootballCount: Int?
            let espnCount: Int?
            let canonicalCount: Int?
            let providerBudgetRemaining: Int?
        }
    }

    struct Match: Decodable {
        struct League: Decodable { let id: String?; let code: String?; let name: String; let logo: String?; let country: String? }
        struct Team: Decodable { let id: String?; let name: String; let logo: String? }
        struct Score: Decodable { let home: Int?; let away: Int? }
        struct Status: Decodable { let code: String; let text: String?; let elapsed: Int? }
        struct ProviderIDs: Decodable { let apiFootball: String?; let espn: String? }
        let canonicalId: String
        let dateUTC: String?
        let league: League
        let home: Team
        let away: Team
        let score: Score
        let status: Status
        let providerIds: ProviderIDs
        let sources: [String]
        let quality: String?
        let warnings: [String]?

        var appMatch: APIPlusMatch {
            let parsedDate = dateUTC.flatMap { raw -> Date? in
                let iso = ISO8601DateFormatter()
                if let date = iso.date(from: raw) { return date }
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return iso.date(from: raw)
            }
            let leagueLogo = league.logo ?? league.id.map { "https://media.api-sports.io/football/leagues/\($0).png" }
            return APIPlusMatch(
                id: canonicalId,
                leagueID: league.id,
                league: league.name,
                leagueLogo: leagueLogo,
                homeID: home.id,
                home: home.name,
                homeLogo: home.logo,
                awayID: away.id,
                away: away.name,
                awayLogo: away.logo,
                homeScore: score.home,
                awayScore: score.away,
                date: parsedDate,
                status: status.code,
                elapsed: status.elapsed
            )
        }
    }

    struct MatchDetail: Decodable {
        let match: Match
        let events: [FlexibleEvent]
        let statistics: [FlexibleTeamStats]
        let lineups: [FlexibleLineup]
        let coverage: Coverage?
        let generatedAt: String?
        struct Coverage: Decodable { let events: String?; let statistics: String?; let lineups: String? }

        var appEvents: [APIEventItem] { events.map(\.appValue) }
        var appStatistics: [APIStatisticTeam] { statistics.map(\.appValue) }
        var appLineups: [APILineupItem] { lineups.compactMap(\.appValue) }
    }

    struct FlexibleEvent: Decodable {
        struct TimeDTO: Decodable { let elapsed: Int?; let extra: Int? }
        struct TeamDTO: Decodable { let id: Int?; let name: String?; let logo: String? }
        struct PersonDTO: Decodable { let id: Int?; let name: String? }
        let time: TimeDTO?
        let minute: String?
        let teamObject: TeamDTO?
        let teamText: String?
        let playerObject: PersonDTO?
        let playerText: String?
        let assist: PersonDTO?
        let type: String?
        let detail: String?
        let text: String?
        let comments: String?

        enum CodingKeys: String, CodingKey { case time, minute, team, player, assist, type, detail, text, comments }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            time = try? c.decodeIfPresent(TimeDTO.self, forKey: .time)
            minute = try? c.decodeIfPresent(String.self, forKey: .minute)
            teamObject = try? c.decodeIfPresent(TeamDTO.self, forKey: .team)
            teamText = try? c.decodeIfPresent(String.self, forKey: .team)
            playerObject = try? c.decodeIfPresent(PersonDTO.self, forKey: .player)
            playerText = try? c.decodeIfPresent(String.self, forKey: .player)
            assist = try? c.decodeIfPresent(PersonDTO.self, forKey: .assist)
            type = try? c.decodeIfPresent(String.self, forKey: .type)
            detail = try? c.decodeIfPresent(String.self, forKey: .detail)
            text = try? c.decodeIfPresent(String.self, forKey: .text)
            comments = try? c.decodeIfPresent(String.self, forKey: .comments)
        }
        var appValue: APIEventItem {
            let parsedMinute = time?.elapsed ?? minute.flatMap { Int($0.prefix { $0.isNumber }) }
            return APIEventItem(
                time: .init(elapsed: parsedMinute, extra: time?.extra),
                team: .init(id: teamObject?.id, name: teamObject?.name ?? teamText, logo: teamObject?.logo),
                player: .init(id: playerObject?.id, name: playerObject?.name ?? playerText),
                assist: .init(id: assist?.id, name: assist?.name),
                type: type,
                detail: detail ?? text,
                comments: comments
            )
        }
    }

    struct FlexibleTeamStats: Decodable {
        struct TeamDTO: Decodable { let id: Int?; let name: String?; let logo: String? }
        struct StatDTO: Decodable {
            let type: String?
            let name: String?
            let value: FlexibleValue?
        }
        let team: TeamDTO
        let statistics: [StatDTO]
        var appValue: APIStatisticTeam {
            APIStatisticTeam(
                team: .init(id: team.id, name: team.name, logo: team.logo),
                statistics: statistics.map { .init(type: $0.type ?? $0.name, value: $0.value?.apiValue) }
            )
        }
    }

    enum FlexibleValue: Decodable {
        case string(String), int(Int), double(Double), null
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() { self = .null }
            else if let v = try? c.decode(Int.self) { self = .int(v) }
            else if let v = try? c.decode(Double.self) { self = .double(v) }
            else { self = .string((try? c.decode(String.self)) ?? "") }
        }
        var apiValue: APIStatValue {
            switch self {
            case .string(let v): return .string(v)
            case .int(let v): return .int(v)
            case .double(let v): return .double(v)
            case .null: return .null
            }
        }
    }

    struct FlexibleLineup: Decodable {
        struct TeamDTO: Decodable { let id: Int?; let name: String?; let logo: String? }
        struct CoachDTO: Decodable { let id: Int?; let name: String?; let photo: String? }
        struct SlotDTO: Decodable {
            struct PlayerDTO: Decodable { let id: Int?; let name: String?; let number: Int?; let pos: String?; let grid: String? }
            let player: PlayerDTO
        }
        struct FlatPlayerDTO: Decodable {
            let id: StringOrInt?
            let name: String?
            let jersey: StringOrInt?
            let position: String?
            let starter: Bool?
        }
        let team: TeamDTO
        let coach: CoachDTO?
        let formation: String?
        let startXI: [SlotDTO]?
        let substitutes: [SlotDTO]?
        let players: [FlatPlayerDTO]?

        var appValue: APILineupItem? {
            let starting: [APILineupItem.Slot]
            let bench: [APILineupItem.Slot]
            if let startXI {
                starting = startXI.map { .init(player: .init(id: $0.player.id, name: $0.player.name, number: $0.player.number, pos: $0.player.pos, grid: $0.player.grid)) }
                bench = (substitutes ?? []).map { .init(player: .init(id: $0.player.id, name: $0.player.name, number: $0.player.number, pos: $0.player.pos, grid: $0.player.grid)) }
            } else {
                let all = players ?? []
                func slot(_ p: FlatPlayerDTO) -> APILineupItem.Slot {
                    .init(player: .init(id: p.id?.intValue, name: p.name, number: p.jersey?.intValue, pos: p.position, grid: nil))
                }
                starting = all.filter { $0.starter == true }.map(slot)
                bench = all.filter { $0.starter != true }.map(slot)
            }
            return APILineupItem(
                team: .init(id: team.id, name: team.name, logo: team.logo),
                coach: coach.map { .init(id: $0.id, name: $0.name, photo: $0.photo) },
                formation: formation,
                startXI: starting,
                substitutes: bench
            )
        }
    }

    enum StringOrInt: Decodable {
        case string(String), int(Int)
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let v = try? c.decode(Int.self) { self = .int(v) }
            else { self = .string((try? c.decode(String.self)) ?? "") }
        }
        var intValue: Int? {
            switch self { case .int(let v): return v; case .string(let v): return Int(v) }
        }
    }

    struct TransfermarktResponse: Decodable {
        struct Item: Decodable, Identifiable {
            var id: String { url }
            let title: String
            let url: String
            let publishedAt: String?
            let source: String?
        }
        let query: String
        let searchURL: String
        let items: [Item]
        let notice: String?
    }

    static func fixtures(date: Date) async throws -> FixturesResponse {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return try await get("api/v2/fixtures", query: [.init(name: "date", value: formatter.string(from: date))])
    }

    static func detail(matchID: String) async throws -> MatchDetail {
        try await get("api/v2/match", query: [.init(name: "id", value: matchID)])
    }

    static func transfermarkt(query: String) async throws -> TransfermarktResponse {
        try await get("api/v2/transfers", query: [.init(name: "q", value: query)])
    }

    private static func get<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> T {
        guard let base = APIFootballClient.backendURL else { throw APIFootballError.missingConfiguration }
        var components = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        guard let url = components.url else { throw APIFootballError.badResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .useProtocolCachePolicy
        request.setValue("NinetyPlus/3.0 iOS", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw APIFootballError.badResponse }
            if http.statusCode == 429 { throw APIFootballError.rateLimited }
            guard (200..<300).contains(http.statusCode) else { throw APIFootballError.serviceUnavailable }
            return try JSONDecoder().decode(T.self, from: data)
        } catch is CancellationError { throw CancellationError() }
        catch let error as APIFootballError { throw error }
        catch { throw APIFootballError.serviceUnavailable }
    }
}
