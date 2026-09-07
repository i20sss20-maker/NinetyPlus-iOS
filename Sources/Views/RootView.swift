import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var network = NetworkStatus.shared
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
        .safeAreaInset(edge: .top, spacing: 0) {
            if !network.isOnline {
                HStack(spacing: 9) {
                    Image(systemName: "wifi.slash")
                    Text("لا يوجد اتصال بالإنترنت — سنعرض آخر بيانات متاحة")
                        .font(.caption.bold())
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.orange.opacity(0.92))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: network.isOnline)
        .task {
            network.start()
            await refreshNow()
        }
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
        guard network.isOnline, APIFootballClient.isConfigured else { return }
        await APISportsStore.shared.refreshToday(force: true)
    }
}
