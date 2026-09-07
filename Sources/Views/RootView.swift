import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var network = NetworkStatus.shared
    @State private var selection = 0
    var body: some View {
        TabView(selection: $selection) {
            V2HomeView(openSearch: { selection = 2 }, openMatches: { selection = 1 }, openNews: { selection = 3 })
                .tag(0).tabItem { Label("الرئيسية", systemImage: "house.fill") }
            V2MatchesView().tag(1).tabItem { Label("المباريات", systemImage: "soccerball") }
            V2DiscoverView().tag(2).tabItem { Label("البحث", systemImage: "magnifyingglass") }
            EnhancedNewsView().tag(3).tabItem { Label("الأخبار", systemImage: "newspaper.fill") }
            V2MoreView().tag(4).tabItem { Label("المزيد", systemImage: "square.grid.2x2.fill") }
        }
        .tint(AppTheme.green).background(AppTheme.bg.ignoresSafeArea())
        .environment(\.locale, SportsDisplayDate.locale)
        .environment(\.calendar, SportsDisplayDate.calendar)
        .environment(\.timeZone, SportsDisplayDate.calendar.timeZone)
        .environment(\.layoutDirection, .rightToLeft)
        .safeAreaInset(edge: .top, spacing: 0) {
            if !network.isOnline {
                Label("لا يوجد اتصال بالإنترنت. نعرض آخر بيانات متاحة.", systemImage: "wifi.slash")
                    .font(.caption).foregroundStyle(.white).frame(maxWidth: .infinity).padding(10).background(Color.orange.opacity(0.85))
            }
        }
        .task { network.start() }
        .task(id: "\(scenePhase == .active):\(network.isOnline):\(selection)") {
            guard scenePhase == .active, network.isOnline, selection == 0 || selection == 1 else { return }
            await refreshNow()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                guard !Task.isCancelled else { return }
                await refreshNow()
            }
        }
    }
    @MainActor private func refreshNow() async {
        guard network.isOnline, APIFootballClient.isConfigured else { return }
        await APISportsStore.shared.refreshToday()
    }
}
