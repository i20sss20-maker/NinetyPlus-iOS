import SwiftUI

struct RootView: View {
    @State private var selection = 0
    var body: some View {
        TabView(selection: $selection) {
            HomeView().tag(0).tabItem { Label("الرئيسية", systemImage: "house.fill") }
            EnhancedMatchesView().tag(1).tabItem { Label("المباريات", systemImage: "soccerball") }
            NewsView().tag(2).tabItem { Label("الأخبار", systemImage: "newspaper.fill") }
            TransfersView().tag(3).tabItem { Label("الانتقالات", systemImage: "arrow.left.arrow.right") }
            MoreView().tag(4).tabItem { Label("المزيد", systemImage: "square.grid.2x2.fill") }
        }
        .tint(AppTheme.green)
        .background(AppTheme.bg.ignoresSafeArea())
        .environment(\.layoutDirection, .rightToLeft)
    }
}
