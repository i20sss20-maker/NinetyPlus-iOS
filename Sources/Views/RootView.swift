import SwiftUI

struct RootView: View {
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            V2HomeView()
                .tag(0)
                .tabItem { Label("الرئيسية", systemImage: "house.fill") }

            V2MatchesView()
                .tag(1)
                .tabItem { Label("المباريات", systemImage: "soccerball") }

            V2DiscoverView()
                .tag(2)
                .tabItem { Label("البحث", systemImage: "magnifyingglass") }

            EnhancedNewsView()
                .tag(3)
                .tabItem { Label("الأخبار", systemImage: "newspaper.fill") }

            V2MoreView()
                .tag(4)
                .tabItem { Label("المزيد", systemImage: "square.grid.2x2.fill") }
        }
        .tint(AppTheme.green)
        .background(AppTheme.bg.ignoresSafeArea())
        .environment(\.layoutDirection, .rightToLeft)
        .task {
            await APISportsStore.shared.refreshToday()
        }
    }
}
