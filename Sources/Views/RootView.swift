import SwiftUI

struct RootView: View {
    @State private var selection = 0
    @State private var showAPISetup = false
    @AppStorage(APIFootballClient.keyDefaultsName) private var apiKey = ""

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
            showAPISetup = apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if !showAPISetup { await APISportsStore.shared.refreshToday() }
        }
        .onChange(of: apiKey) { _, value in
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            Task { await APISportsStore.shared.refreshToday(force: true) }
        }
        .sheet(isPresented: $showAPISetup) { APIKeySetupView() }
    }
}
