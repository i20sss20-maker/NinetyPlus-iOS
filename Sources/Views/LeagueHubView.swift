import SwiftUI

// Legacy compatibility wrapper. Production league pages use V2 + Railway.
struct LeagueHubView: View {
    let league: LeagueOption
    var body: some View { V2LeagueHubView(league: league) }
}
