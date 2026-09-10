import Foundation

extension LeagueOption {
    var apiFootballID: String {
        if id.hasPrefix("api-football:") { return String(id.dropFirst("api-football:".count)) }
        switch id {
        case "4668": return "307"
        case "4328": return "39"
        case "4335": return "140"
        case "4331": return "78"
        case "4332": return "135"
        case "4334": return "61"
        default: return id
        }
    }

    static func fromFixtureLeague(id: String, name: String) -> LeagueOption? {
        guard !id.isEmpty, id.utf8.allSatisfy({ (48...57).contains($0) }),
              let number = Int(id), number > 0 else { return nil }
        if let existing = featured.first(where: { $0.apiFootballID == id }) { return existing }
        // A real API-Football ID can equal a legacy TheSportsDB shortcut ID.
        // Keep that namespace explicit instead of accidentally remapping it.
        return LeagueOption(id: "api-football:\(id)", arabicName: name, englishName: name)
    }
}
