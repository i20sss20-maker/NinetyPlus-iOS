import SwiftUI

// Legacy entry points kept only for source compatibility.
// Production UI lives in V2 and uses the Railway backend for football data.

struct MatchesView: View {
    var body: some View { V2MatchesView() }
}

struct MatchDetailView: View {
    let match: LiveMatch

    var body: some View {
        V2MatchCenterView(match: APIPlusMatch(
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
            status: match.status,
            elapsed: nil
        ))
    }
}

struct NewsView: View {
    var body: some View { EnhancedNewsView() }
}

struct TransfersView: View {
    var body: some View { EnhancedTransfersView() }
}

struct ProfileView: View {
    var body: some View { V2MoreView() }
}
