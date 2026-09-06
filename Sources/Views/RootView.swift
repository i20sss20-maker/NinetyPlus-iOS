import SwiftUI

struct RootView: View {
    @State private var selection = 0
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = SportsStore.shared

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tag(0)
                .tabItem { Label("الرئيسية", systemImage: "house.fill") }

            EnhancedMatchesView()
                .tag(1)
                .tabItem { Label("المباريات", systemImage: "soccerball") }

            NavigationStack { DiscoverView() }
                .tag(2)
                .tabItem { Label("البحث", systemImage: "magnifyingglass") }

            EnhancedNewsView()
                .tag(3)
                .tabItem { Label("الأخبار", systemImage: "newspaper.fill") }

            MoreView()
                .tag(4)
                .tabItem { Label("المزيد", systemImage: "square.grid.2x2.fill") }
        }
        .tint(AppTheme.green)
        .background(AppTheme.bg.ignoresSafeArea())
        .environment(\.layoutDirection, .rightToLeft)
        .task { await store.refreshIfStale(maxAge: 90) }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await store.refreshIfStale(maxAge: 90) }
        }
    }
}
