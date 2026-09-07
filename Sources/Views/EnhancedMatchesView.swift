import SwiftUI

// Legacy entry point kept for source compatibility.
// All production match browsing now uses the Railway-backed V2 experience.
struct EnhancedMatchesView: View {
    var body: some View {
        V2MatchesView()
    }
}
