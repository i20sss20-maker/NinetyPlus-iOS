import Foundation

@main struct LeagueRoutingTests {
    static func main() {
        precondition(LeagueOption.fromFixtureLeague(id: "307", name: "Saudi")?.id == "4668")
        precondition(LeagueOption.fromFixtureLeague(id: "253", name: "MLS")?.apiFootballID == "253")
        precondition(LeagueOption.fromFixtureLeague(id: "4668", name: "Another league")?.apiFootballID == "4668",
                     "Provider ID must not be mistaken for a legacy catalogue ID")
        for id in ["", "0", "-1", "espn:123", "ksa.1", "الدوري", "٣٠٧", "1/teams", "99999999999999999999999"] {
            precondition(LeagueOption.fromFixtureLeague(id: id, name: "Unknown") == nil)
        }
        for league in LeagueOption.featured {
            precondition(LeagueOption.fromFixtureLeague(id: league.apiFootballID, name: league.arabicName)?.id == league.id)
        }
        print("League routing: featured, non-featured, namespace collisions and invalid IDs passed")
    }
}
