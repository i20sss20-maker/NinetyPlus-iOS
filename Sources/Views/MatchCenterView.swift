import SwiftUI

// Legacy entry point kept only for source compatibility with older screens.
// It adapts the old lightweight match model into the production V2 match center.
struct MatchCenterView: View {
    let match: LiveMatch

    var body: some View {
        V2MatchCenterView(match: adaptedMatch)
    }

    private var adaptedMatch: APIPlusMatch {
        APIPlusMatch(
            id: match.id,
            leagueID: nil,
            league: match.league,
            leagueLogo: nil,
            homeID: nil,
            home: match.home,
            homeLogo: match.homeBadge,
            awayID: nil,
            away: match.away,
            awayLogo: match.awayBadge,
            homeScore: match.homeScore.flatMap(Int.init),
            awayScore: match.awayScore.flatMap(Int.init),
            date: nil,
            status: normalizedStatus(match.status),
            elapsed: nil
        )
    }

    private func normalizedStatus(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = value.lowercased()
        if lower == "ft" || lower.contains("finished") { return "FT" }
        if lower == "ht" || lower.contains("half time") { return "HT" }
        if lower.contains("not started") || lower.contains("scheduled") { return "NS" }
        if lower.contains("postpon") { return "PST" }
        if lower.contains("cancel") { return "CANC" }
        if lower.contains("penalt") { return "PEN" }
        if lower.contains("extra time") { return "AET" }
        if lower.contains("live") || lower.contains("in progress") || lower == "1h" || lower == "2h" { return "LIVE" }
        return value
    }
}
