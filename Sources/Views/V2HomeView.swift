import SwiftUI

extension APIPlusMatch: FollowedMatchSummary {}

@MainActor
private final class ForYouStore: ObservableObject {
    @Published private(set) var progress = ForYouProgress<APIPlusMatch>()

    func cancelPending() { progress.invalidate() }

    func load(teamIDs: [String], force: Bool = false) async {
        guard !Task.isCancelled else { return }
        progress.select(teamIDs)
        let selection = progress.teamIDs
        let pending = progress.pendingIDs(force: force)
        // All followed clubs are included. Only three requests run at once.
        for start in stride(from: 0, to: pending.count, by: 3) {
            guard !Task.isCancelled, progress.teamIDs == selection else { return }
            let batch = Array(pending[start..<min(start + 3, pending.count)])
            await withTaskGroup(of: Void.self) { group in
                for id in batch {
                    group.addTask { await self.loadClub(id, force: force) }
                }
            }
        }
    }

    private func loadClub(_ id: String, force: Bool) async {
        guard !Task.isCancelled, let token = progress.begin(id, force: force) else { return }
        defer { progress.cancel(id, token: token) }
        do {
            let matches = try await APISportsStore.shared.teamFixtures(teamID: id, next: true)
            try Task.checkCancellation()
            progress.succeed(id, items: matches, token: token)
        } catch {
            guard !Task.isCancelled, !(error is CancellationError),
                  (error as? URLError)?.code != .cancelled else { return }
            progress.fail(id, message: error.localizedDescription, token: token)
        }
    }
}

struct V2HomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var api = APISportsStore.shared
    @StateObject private var content = EditorialStore.shared
    @StateObject private var favorites = ForYouStore()
    @AppStorage("favoriteTeamIDs") private var favoriteTeamIDs = ""
    @AppStorage("favoritePlayerIDs") private var favoritePlayerIDs = ""
    @State private var visible = false
    @State private var favoriteRetryID = 0
    @State private var todayRetryID = 0
    @State private var newsRetryID = 0

    private var isActive: Bool { visible && scenePhase == .active }
    private var teamIDs: [String] { SavedFavoriteIDs.parse(favoriteTeamIDs) }
    private var playerCount: Int { SavedFavoriteIDs.parse(favoritePlayerIDs).count }
    private var live: [APIPlusMatch] { api.today.filter { api.isLive($0.status) } }
    private var forYouMatches: [APIPlusMatch] {
        ForYouMatchSelection.merge(
            today: api.today, upcoming: favorites.progress.values, teamIDs: Set(teamIDs),
            startOfToday: Calendar.current.startOfDay(for: Date()), isLive: { api.isLive($0) }
        )
    }
    private var favoriteWarning: String? {
        guard favorites.progress.teamIDs == teamIDs else { return nil }
        let failed = favorites.progress.failures
        guard let first = failed.first else { return nil }
        let detail = favorites.progress.state(first).errorMessage ?? "حاول مرة أخرى بعد قليل."
        return "تعذر تحديث مباريات \(failed.count) من \(teamIDs.count) أندية. \(detail) اختياراتك محفوظة."
    }
    private var validNews: [RealArticle] {
        content.news.filter { article in
            guard !article.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let url = article.url, let host = url.host, !host.isEmpty else { return false }
            return ["https", "http"].contains(url.scheme?.lowercased() ?? "")
        }.sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    TopBar(title: nil, showsLogo: true)
                    liveHero
                    forYouSection
                    todaySection
                    quickActions
                    newsSection
                }.padding(.bottom, 28)
            }
            .background(AppTheme.bg.ignoresSafeArea())
            .onAppear { visible = true }
            .onDisappear { visible = false; favorites.cancelPending() }
            .task(id: "\(isActive):\(teamIDs.joined(separator: ",")):\(favoriteRetryID)") {
                guard isActive else { return }
                await favorites.load(teamIDs: teamIDs)
            }
            .task(id: "\(isActive):news:\(newsRetryID)") {
                guard isActive else { return }
                if newsRetryID > 0 { await content.refresh() }
                else { await content.refreshIfStale(maxAge: 180) }
            }
            .task(id: "\(isActive):today:\(todayRetryID)") {
                guard isActive, todayRetryID > 0 else { return }
                await api.refreshToday(force: true)
            }
            .refreshable {
                guard isActive else { return }
                async let a: Void = api.refreshToday(force: true)
                async let b: Void = content.refresh()
                async let c: Void = favorites.load(teamIDs: teamIDs, force: true)
                _ = await (a, b, c)
            }
        }
    }

    @ViewBuilder private var liveHero: some View {
        if let match = live.first ?? api.today.first {
            NavigationLink { V2MatchCenterView(match: match) } label: {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label(live.isEmpty ? "أبرز مباراة" : "مباشر الآن", systemImage: live.isEmpty ? "star.fill" : "dot.radiowaves.left.and.right")
                            .font(.caption.bold()).foregroundStyle(live.isEmpty ? AppTheme.muted : AppTheme.green)
                        Spacer()
                        Text(match.league).font(.caption).foregroundStyle(AppTheme.muted).lineLimit(1)
                    }
                    HStack(spacing: 14) {
                        heroTeam(match.home, match.homeLogo)
                        Spacer()
                        VStack(spacing: 5) {
                            if !FixturePhase.isUpcoming(match.status), let h = match.homeScore, let a = match.awayScore {
                                Text("\(h) - \(a)").font(.system(size: 31, weight: .black, design: .rounded)).monospacedDigit()
                            } else if let date = match.date { Text(date, style: .time).font(.title2.bold()) }
                            else { Text("—").font(.title2.bold()) }
                            Text(MatchLivePolicy.statusText(match.status, elapsed: match.elapsed))
                                .font(.caption.bold()).foregroundStyle(AppTheme.green)
                        }
                        Spacer()
                        heroTeam(match.away, match.awayLogo)
                    }
                    if api.error != nil {
                        Label("تعذر تحديث النتيجة؛ هذه آخر بيانات مستلمة.", systemImage: "clock.arrow.circlepath")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                .foregroundStyle(.white).padding(18)
                .background(LinearGradient(colors: [AppTheme.card, AppTheme.green.opacity(0.12)], startPoint: .topTrailing, endPoint: .bottomLeading), in: RoundedRectangle(cornerRadius: 24))
                .padding(.horizontal, 16)
            }.buttonStyle(.plain)
        }
    }

    private var forYouSection: some View {
        VStack(spacing: 10) {
            sectionHeader("لك", subtitle: "\(teamIDs.count) نادي • \(playerCount) لاعب")
            if teamIDs.isEmpty {
                followLink(
                    title: playerCount == 0 ? "خصص صفحة لك" : "متابعة اللاعبين محفوظة",
                    message: "تابع أنديتك لتظهر مبارياتها هنا، وافتح مركز المتابعة للوصول إلى أنديتك ولاعبيك."
                )
            } else {
                PageLoadFeedback(
                    loading: favorites.progress.isLoading || favorites.progress.teamIDs != teamIDs,
                    hasValue: !forYouMatches.isEmpty || (favorites.progress.teamIDs == teamIDs && favorites.progress.hasValue),
                    message: favoriteWarning,
                    updatedAt: favorites.progress.teamIDs == teamIDs ? favorites.progress.lastUpdated : nil
                ) { favoriteRetryID += 1 }
                ForEach(forYouMatches.prefix(6)) { match in
                    NavigationLink { V2MatchCenterView(match: match) } label: {
                        APICompactMatchCard(match: match)
                    }.buttonStyle(.plain)
                }
                if forYouMatches.isEmpty, favorites.progress.teamIDs == teamIDs, favorites.progress.mayShowEmpty {
                    followLink(title: "متابعاتك محفوظة", message: "لم ينشر المصدر مباريات قادمة للأندية التي تتابعها حاليًا. اسحب للتحديث أو افتح مركز المتابعة.")
                } else {
                    NavigationLink { V2FavoritesView() } label: {
                        Label("كل متابعاتك", systemImage: "star").font(.caption.bold()).foregroundStyle(AppTheme.green)
                    }
                }
            }
        }
    }

    private var todaySection: some View {
        VStack(spacing: 10) {
            sectionHeader("مباريات اليوم", subtitle: api.lastUpdated == nil ? nil : "\(api.today.count) مباراة")
            PageLoadFeedback(
                loading: APIFootballClient.isConfigured && (api.loading || (api.lastUpdated == nil && api.error == nil)),
                hasValue: api.lastUpdated != nil,
                message: APIFootballClient.isConfigured ? api.error : "خدمة المباريات غير متاحة حاليًا.",
                updatedAt: api.lastUpdated
            ) { todayRetryID += 1 }
            if api.lastUpdated != nil, !api.loading, api.error == nil, api.today.isEmpty {
                emptyCard("لا توجد مباريات منشورة لهذا اليوم", icon: "soccerball")
            }
            ForEach(api.today.prefix(6)) { match in
                NavigationLink { V2MatchCenterView(match: match) } label: {
                    APICompactMatchCard(match: match)
                }.buttonStyle(.plain)
            }
        }
    }

    private var quickActions: some View {
        VStack(spacing: 10) {
            sectionHeader("استكشف 90+", subtitle: nil)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    NavigationLink { V2DiscoverView() } label: { quickCard("بحث", icon: "magnifyingglass") }
                    if let saudi = LeagueOption.featured.first {
                        NavigationLink { V2LeagueHubView(league: saudi) } label: { quickCard("الدوري السعودي", icon: "list.number") }
                    }
                    NavigationLink { V2FavoritesView() } label: { quickCard("لك", icon: "star.fill") }
                    NavigationLink { EnhancedTransfersView() } label: { quickCard("الانتقالات", icon: "arrow.left.arrow.right") }
                    NavigationLink { V2MatchesView() } label: { quickCard("كل المباريات", icon: "calendar") }
                }.padding(.horizontal, 16)
            }.buttonStyle(.plain)
        }
    }

    private var newsSection: some View {
        VStack(spacing: 10) {
            sectionHeader("آخر الأخبار", subtitle: "روابط المصادر")
            PageLoadFeedback(
                loading: content.isLoading, hasValue: !validNews.isEmpty,
                message: content.errorMessage, updatedAt: content.lastUpdated
            ) { newsRetryID += 1 }
            if !content.isLoading, content.errorMessage == nil, validNews.isEmpty {
                emptyCard("لا توجد أخبار منشورة متاحة حاليًا", icon: "newspaper")
            }
            ForEach(validNews.prefix(4)) { article in
                if let url = article.url {
                    Link(destination: url) {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 12).fill(AppTheme.green.opacity(0.12)).frame(width: 52, height: 52)
                                .overlay { Image(systemName: "newspaper.fill").foregroundStyle(AppTheme.green) }
                            VStack(alignment: .leading, spacing: 5) {
                                Text(article.title).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(2)
                                HStack(spacing: 6) {
                                    Text(article.source); Text("•"); Text(article.date, style: .relative)
                                }.font(.caption2).foregroundStyle(AppTheme.muted)
                            }
                            Spacer(minLength: 0)
                        }.padding(12).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func followLink(title: String, message: String) -> some View {
        NavigationLink { V2FavoritesView() } label: {
            HStack(spacing: 14) {
                Image(systemName: "star.circle.fill").font(.system(size: 34)).foregroundStyle(AppTheme.green)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(.white)
                    Text(message).font(.caption).foregroundStyle(AppTheme.muted).multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.left").foregroundStyle(AppTheme.muted)
            }.padding(16).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20)).padding(.horizontal, 16)
        }.buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String, subtitle: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.bold()); Spacer()
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(AppTheme.muted) }
        }.padding(.horizontal, 16)
    }
    private func heroTeam(_ name: String, _ logo: String?) -> some View {
        VStack(spacing: 7) {
            RemoteBadge(url: logo).frame(width: 64, height: 64)
            Text(name).font(.subheadline.bold()).multilineTextAlignment(.center).lineLimit(2).frame(width: 100)
        }
    }
    private func quickCard(_ title: String, icon: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: icon).font(.title2.bold()).foregroundStyle(AppTheme.green)
            Text(title).font(.caption.bold()).foregroundStyle(.white).lineLimit(1)
        }.frame(width: 112, height: 88).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }
    private func emptyCard(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon).font(.subheadline).foregroundStyle(AppTheme.muted)
            .frame(maxWidth: .infinity).padding(22).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
    }
}
