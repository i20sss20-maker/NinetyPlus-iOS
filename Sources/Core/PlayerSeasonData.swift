import Foundation

/// Shared by player profiles and the scoring table. API-Football spells its
/// appearance field "appearences"; accept the conventional spelling as well.
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
        struct Games: Decodable {
            let appearances: Int?
            let minutes: Int?
            let position: String?
            let rating: String?
            private enum CodingKeys: String, CodingKey {
                case providerAppearances = "appearences"
                case appearances, minutes, position, rating
            }
            init(from decoder: Decoder) throws {
                let fields = try decoder.container(keyedBy: CodingKeys.self)
                // An explicit null from the provider stays unknown, not zero.
                appearances = try fields.decodeIfPresent(Int.self, forKey: fields.contains(.providerAppearances) ? .providerAppearances : .appearances)
                minutes = try fields.decodeIfPresent(Int.self, forKey: .minutes)
                position = try fields.decodeIfPresent(String.self, forKey: .position)
                rating = try fields.decodeIfPresent(String.self, forKey: .rating)
            }
        }
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

/// Unknown statistics must remain optional all the way to the displayed metric.
struct APIPlusPlayerSeasonStat: Identifiable, Hashable {
    let id: String
    let league: String
    let leagueLogo: String?
    let teamID: String?
    let team: String
    let teamLogo: String?
    let appearances: Int?
    let minutes: Int?
    let position: String?
    let rating: String?
    let goals: Int?
    let assists: Int?
    let yellowCards: Int?
    let redCards: Int?

    init(playerID: String, index: Int, statistic: APITopScorerItem.Statistic) {
        id = "\(playerID)-\(statistic.league?.id ?? index)-\(statistic.team.id ?? index)-\(index)"
        league = statistic.league?.name ?? "البطولة غير محددة"
        leagueLogo = statistic.league?.logo
        teamID = statistic.team.id.map(String.init)
        team = statistic.team.name ?? "الفريق غير محدد"
        teamLogo = statistic.team.logo
        appearances = statistic.games?.appearances
        minutes = statistic.games?.minutes
        position = statistic.games?.position
        rating = statistic.games?.rating
        goals = statistic.goals?.total
        assists = statistic.goals?.assists
        yellowCards = statistic.cards?.yellow
        redCards = statistic.cards?.red
    }
}
