import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
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
        .task { await refreshNow() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await refreshNow()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { break }
                await refreshNow()
            }
        }
    }

    @MainActor private func refreshNow() async {
        guard APIFootballClient.isConfigured else { return }
        await APISportsStore.shared.refreshToday(force: true)
    }
}
