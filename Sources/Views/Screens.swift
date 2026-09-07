import SwiftUI

// Legacy entry points kept only for source compatibility.
// Production UI lives in V2.

struct MatchesView: View {
    var body: some View { V2MatchesView() }
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
