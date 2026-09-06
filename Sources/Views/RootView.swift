import SwiftUI

struct RootView: View {
    @State private var selection = 0
    @State private var showAPISetup = false
    @AppStorage(APIFootballClient.keyDefaultsName) private var apiKey = ""
    @AppStorage(APIFootballClient.backendURLDefaultsName) private var backendURL = ""

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
            showAPISetup = !APIFootballClient.isConfigured
            if APIFootballClient.isConfigured { await APISportsStore.shared.refreshToday() }
        }
        .onChange(of: apiKey) { _, _ in refreshConfiguration() }
        .onChange(of: backendURL) { _, _ in refreshConfiguration() }
        .sheet(isPresented: $showAPISetup) { APIKeySetupView() }
    }

    private func refreshConfiguration() {
        showAPISetup = !APIFootballClient.isConfigured
        guard APIFootballClient.isConfigured else { return }
        Task { await APISportsStore.shared.refreshToday(force: true) }
    }
}
