import SwiftUI

extension APIPlusMatch: FollowedMatchSummary {}
@MainActor private final class ForYouStore: ObservableObject {
    @Published private(set) var progress = ForYouProgress<APIPlusMatch>()
    func cancelPending() { progress.invalidate() }
    func load(teamIDs: [String], force: Bool = false) async {
        guard !Task.isCancelled else { return }
        progress.select(teamIDs)
        let selection = progress.teamIDs
        let pending = progress.pendingIDs(force: force)
        for start in stride(from: 0, to: pending.count, by: 3) {
            guard !Task.isCancelled, progress.teamIDs == selection else { return }
            let batch = Array(pending[start..<min(start + 3, pending.count)])
            await withTaskGroup(of: Void.self) { group in
                for id in batch { group.addTask { await self.loadClub(id, force: force) } }
            }
        }
    }
    private func loadClub(_ id: String, force: Bool) async {
        guard !Task.isCancelled, let token = progress.begin(id, force: force) else { return }
        defer { progress.cancel(id, token: token) }
        do {
            let items = try await APISportsStore.shared.teamFixtures(teamID: id, next: true)
            try Task.checkCancellation(); progress.succeed(id, items: items, token: token)
        } catch {
            if !Task.isCancelled && !(error is CancellationError) { progress.fail(id, message: error.localizedDescription, token: token) }
        }
    }
}

struct V2HomeView: View {
    let openSearch: () -> Void
    let openMatches: () -> Void
    let openNews: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var api = APISportsStore.shared
    @StateObject private var editorial = EditorialStore.shared
    @StateObject private var favorites = ForYouStore()
    @AppStorage("favoriteTeamIDs") private var favoriteTeamIDs = ""
    @AppStorage("ninetyplus.favoriteLeagueIDs") private var favoriteLeagueIDs = ""
    @State private var visible = false
    @State private var favoriteRetry = 0
    @State private var todayRetry = 0
    @State private var newsRetry = 0
    private var active: Bool { visible && scenePhase == .active }
    private var teams: [String] { SavedFavoriteIDs.parse(favoriteTeamIDs) }
    private var leagues: Set<String> { Set(SavedFavoriteIDs.parse(favoriteLeagueIDs)) }
    private var today: [APIPlusMatch] {
        api.today.filter { $0.date.map { SportsDisplayDate.calendar.isDateInToday($0) } ?? true }.sorted { a, b in
            let pa = priority(a), pb = priority(b)
            if pa != pb { return pa < pb }
            if a.date != b.date { return (a.date ?? .distantFuture) < (b.date ?? .distantFuture) }
            return a.id < b.id
        }
    }
    private var personal: [APIPlusMatch] {
        ForYouMatchSelection.merge(today: today, upcoming: favorites.progress.values, teamIDs: Set(teams), startOfToday: SportsDisplayDate.calendar.startOfDay(for: Date()), isLive: MatchLivePolicy.isLive)
    }
    private var orderedLeagues: [LeagueOption] {
        LeagueOption.featured.filter { leagues.contains($0.apiFootballID) } + LeagueOption.featured.filter { !leagues.contains($0.apiFootballID) }
    }
    private func priority(_ match: APIPlusMatch) -> Int {
        let followed = match.homeID.map { teams.contains($0) } == true || match.awayID.map { teams.contains($0) } == true
        let important = ["307", "2", "39", "140", "135", "78", "61", "17"].contains(match.leagueID ?? "")
        let phase = MatchLivePolicy.isLive(match.status) ? 0 : (FixturePhase.isUpcoming(match.status) ? 10 : 20)
        return (followed ? 0 : (important ? 40 : 80)) + phase + (leagues.contains(match.leagueID ?? "") ? 0 : 5)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 22) {
                    header
                    leagueSection
                    if let match = today.first {
                        NavigationLink { V2MatchCenterView(match: match).toolbar(.visible, for: .navigationBar) } label: { DashboardMatchHero(match: match) }
                            .buttonStyle(.plain).accessibilityIdentifier("home.featuredMatch")
                    }
                    todaySection
                    personalSection
                    newsSection
                }.padding(.vertical, 12).padding(.bottom, 24)
            }.background(AppTheme.bg.ignoresSafeArea()).toolbar(.hidden, for: .navigationBar)
                .onAppear { visible = true }.onDisappear { visible = false; favorites.cancelPending() }
                .task(id: "\(active):\(teams.joined(separator: ",")):\(favoriteRetry)") {
                    if active { await favorites.load(teamIDs: teams) }
                }
                .task(id: "\(active):news:\(newsRetry)") {
                    guard active else { return }
                    if newsRetry > 0 { await editorial.refresh() } else { await editorial.refreshIfStale(maxAge: 300) }
                }
                .task(id: "\(active):today:\(todayRetry)") { if active && todayRetry > 0 { await api.refreshToday(force: true) } }
                .refreshable {
                    guard active else { return }
                    async let a: Void = api.refreshToday(force: true)
                    async let b: Void = editorial.refresh()
                    async let c: Void = favorites.load(teamIDs: teams, force: true)
                    _ = await (a, b, c)
                }
        }
    }
    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                BrandLogo().environment(\.layoutDirection, .leftToRight)
                Text(SportsDisplayDate.label(Date())).font(.caption).foregroundStyle(AppTheme.muted)
            }
            Spacer()
            NavigationLink { V2FavoritesView().toolbar(.visible, for: .navigationBar) } label: { headerIcon("star", label: "متابعاتي") }
                .accessibilityIdentifier("home.favorites")
            Button(action: openSearch) { headerIcon("magnifyingglass", label: "البحث") }.accessibilityIdentifier("home.search")
        }.buttonStyle(.plain).padding(.horizontal, 20)
    }
    private func headerIcon(_ symbol: String, label: String) -> some View {
        Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 44, height: 44).background(AppTheme.cardRaised, in: Circle()).overlay(Circle().stroke(AppTheme.border)).accessibilityLabel(label)
    }
    private func heading(_ title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.bold()).foregroundStyle(.white); Spacer()
            if let actionTitle, let action { Button(actionTitle, action: action).font(.caption.bold()).foregroundStyle(AppTheme.green) }
        }.padding(.horizontal, 20)
    }
    private var leagueSection: some View {
        VStack(spacing: 12) {
            heading(leagues.isEmpty ? "البطولات" : "بطولاتك والمزيد")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(orderedLeagues) { league in
                        VStack(spacing: 6) {
                            NavigationLink { V2LeagueHubView(league: league) } label: {
                                VStack(spacing: 8) {
                                    RemoteBadge(url: "https://media.api-sports.io/football/leagues/\(league.apiFootballID).png").frame(width: 42, height: 42)
                                    Text(league.arabicName).font(.caption.bold()).foregroundStyle(.white).multilineTextAlignment(.center).lineLimit(2).frame(height: 30)
                                }.frame(maxWidth: .infinity)
                            }.accessibilityIdentifier("home.league.\(league.apiFootballID)")
                            Button { toggleLeague(league.apiFootballID) } label: {
                                Label(leagues.contains(league.apiFootballID) ? "متابَع" : "متابعة", systemImage: leagues.contains(league.apiFootballID) ? "star.fill" : "plus")
                                    .font(.caption2.bold()).foregroundStyle(AppTheme.green).frame(minHeight: 32)
                            }.accessibilityIdentifier("home.followLeague.\(league.apiFootballID)")
                        }.padding(10).frame(width: 108).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 20))
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(leagues.contains(league.apiFootballID) ? AppTheme.green.opacity(0.5) : AppTheme.border))
                    }
                }.padding(.horizontal, 16)
            }.buttonStyle(.plain)
        }
    }
    private func toggleLeague(_ id: String) {
        var selected = leagues
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        favoriteLeagueIDs = selected.sorted().joined(separator: ",")
    }
    private var todaySection: some View {
        VStack(spacing: 10) {
            heading("مباريات اليوم", actionTitle: "كل المباريات", action: openMatches)
            DashboardFeedback(loading: api.loading || (api.lastUpdated == nil && api.error == nil), hasContent: !today.isEmpty, error: api.error) { todayRetry += 1 }
            ForEach(Array(today.dropFirst().prefix(3))) { match in
                NavigationLink { V2MatchCenterView(match: match).toolbar(.visible, for: .navigationBar) } label: { DashboardMatchRow(match: match) }.buttonStyle(.plain)
            }
            if today.isEmpty, !api.loading, api.error == nil, api.lastUpdated != nil {
                Text("لا توجد مباريات منشورة لهذا اليوم.").font(.subheadline).foregroundStyle(AppTheme.muted).padding(22)
            }
            Text("المواعيد بتوقيت الرياض").font(.caption2).foregroundStyle(AppTheme.muted)
        }
    }
    private var personalSection: some View {
        VStack(spacing: 10) {
            heading("لك")
            if teams.isEmpty {
                NavigationLink { V2FavoritesView().toolbar(.visible, for: .navigationBar) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "star.circle.fill").font(.largeTitle).foregroundStyle(AppTheme.green)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("أنديتك في مكان واحد").font(.headline).foregroundStyle(.white)
                            Text("اختر أنديتك لتتابع مبارياتها خلال الأيام السبعة القادمة.").font(.caption).foregroundStyle(AppTheme.muted)
                        }
                        Spacer(minLength: 0); Image(systemName: "chevron.left").font(.caption.bold()).foregroundStyle(AppTheme.green)
                    }.padding(18).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 20)).padding(.horizontal, 16)
                }.buttonStyle(.plain)
            } else {
                DashboardFeedback(loading: favorites.progress.isLoading, hasContent: !personal.isEmpty, error: favorites.progress.failures.isEmpty ? nil : "تعذر تحديث مباريات بعض الأندية. متابعاتك محفوظة.") { favoriteRetry += 1 }
                ForEach(personal.prefix(4)) { match in
                    NavigationLink { V2MatchCenterView(match: match).toolbar(.visible, for: .navigationBar) } label: { DashboardMatchRow(match: match) }.buttonStyle(.plain)
                }
                if personal.isEmpty, favorites.progress.mayShowEmpty {
                    Text("لا توجد مباريات منشورة لأنديتك خلال الأيام السبعة القادمة.").font(.caption).foregroundStyle(AppTheme.muted).padding(16)
                }
            }
        }
    }
    private var newsSection: some View {
        VStack(spacing: 12) {
            heading("آخر الأخبار", actionTitle: "كل الأخبار", action: openNews)
            DashboardFeedback(loading: editorial.isLoading, hasContent: !editorial.news.isEmpty, error: editorial.newsError) { newsRetry += 1 }
            ForEach(editorial.news.prefix(5)) { article in
                if let url = article.url { Link(destination: url) { DashboardNewsCard(article: article) }.buttonStyle(.plain) }
            }
        }
    }
}

private struct DashboardFeedback: View {
    let loading: Bool; let hasContent: Bool; let error: String?; let retry: () -> Void
    var body: some View {
        Group {
            if let error {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(error).font(.caption).foregroundStyle(AppTheme.muted)
                        if hasContent { Text("نعرض آخر بيانات متاحة.").font(.caption2).foregroundStyle(AppTheme.muted) }
                    }
                    Spacer(minLength: 0)
                    Button("إعادة المحاولة", action: retry).font(.caption.bold()).foregroundStyle(AppTheme.green).disabled(loading)
                }.padding(14).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 16)
            } else if loading && !hasContent { ProgressView("جارٍ التحميل…").tint(AppTheme.green).font(.caption).padding(24) }
        }
    }
}

private struct DashboardMatchHero: View {
    let match: APIPlusMatch
    private var live: Bool { MatchLivePolicy.isLive(match.status) }
    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                RemoteBadge(url: match.leagueLogo).frame(width: 26, height: 26)
                Text(SportsArabic.league(match.league)).font(.caption.bold()).lineLimit(2)
                Spacer(minLength: 8)
                Text(MatchLivePolicy.statusText(match.status, elapsed: nil)).font(.caption2.bold()).foregroundStyle(AppTheme.green)
                    .padding(.horizontal, 10).padding(.vertical, 7).background(AppTheme.green.opacity(0.1), in: Capsule())
            }
            HStack(alignment: .center, spacing: 6) {
                team(match.home, logo: match.homeLogo)
                VStack(spacing: 7) {
                    if !FixturePhase.isUpcoming(match.status), let home = match.homeScore, let away = match.awayScore {
                        HStack(spacing: 8) { Text(String(home)); Text(":").foregroundStyle(AppTheme.muted); Text(String(away)) }
                            .font(.system(size: 36, weight: .black, design: .rounded)).monospacedDigit()
                    } else if let date = match.date { Text(SportsDisplayDate.label(date, pattern: "HH:mm")).font(.title2.bold()).monospacedDigit() }
                    else { Text("—").font(.title2.bold()) }
                    if live, let minute = match.elapsed { Text("\(minute)′").font(.caption.bold()).foregroundStyle(AppTheme.green) }
                }.frame(maxWidth: .infinity).minimumScaleFactor(0.7).lineLimit(1)
                team(match.away, logo: match.awayLogo)
            }
            HStack {
                if let date = match.date { Text(SportsDisplayDate.label(date, pattern: "d MMMM")).font(.caption).foregroundStyle(AppTheme.muted) }
                Spacer(); Label("مركز المباراة", systemImage: "chevron.left").font(.caption.bold()).foregroundStyle(AppTheme.green)
            }
        }.foregroundStyle(.white).padding(20)
            .background(LinearGradient(colors: [AppTheme.cardRaised, AppTheme.greenDeep.opacity(0.2)], startPoint: .topTrailing, endPoint: .bottomLeading), in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(AppTheme.green.opacity(0.2))).padding(.horizontal, 16)
    }
    private func team(_ name: String, logo: String?) -> some View {
        VStack(spacing: 10) { RemoteBadge(url: logo).frame(width: 60, height: 60); Text(SportsArabic.team(name)).font(.subheadline.bold()).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8) }.frame(maxWidth: .infinity)
    }
}

private struct DashboardMatchRow: View {
    let match: APIPlusMatch
    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 9) { club(match.home, logo: match.homeLogo); club(match.away, logo: match.awayLogo) }
            Spacer(minLength: 4)
            if !FixturePhase.isUpcoming(match.status), let home = match.homeScore, let away = match.awayScore {
                VStack(spacing: 9) { Text(String(home)).frame(height: 26); Text(String(away)).frame(height: 26) }.font(.headline.bold()).monospacedDigit()
            } else if let date = match.date { Text(SportsDisplayDate.label(date, pattern: "HH:mm")).font(.subheadline.bold()).monospacedDigit() }
            VStack(spacing: 5) {
                Text(MatchLivePolicy.statusText(match.status, elapsed: match.elapsed)).font(.caption2.bold()).multilineTextAlignment(.center)
                if let date = match.date, !SportsDisplayDate.calendar.isDateInToday(date) { Text(SportsDisplayDate.label(date, pattern: "d MMM")).font(.caption2) }
            }.foregroundStyle(MatchLivePolicy.isLive(match.status) ? AppTheme.green : AppTheme.muted).frame(maxWidth: 76)
        }.foregroundStyle(.white).padding(14).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppTheme.border)).padding(.horizontal, 16)
    }
    private func club(_ name: String, logo: String?) -> some View {
        HStack(spacing: 9) { RemoteBadge(url: logo).frame(width: 26, height: 26); Text(SportsArabic.team(name)).font(.subheadline.weight(.semibold)).lineLimit(1); Spacer(minLength: 0) }
    }
}

private struct DashboardNewsCard: View {
    let article: RealArticle
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if article.imageURL != nil { EditorialArtwork(article: article).frame(width: 104, height: 92).clipShape(RoundedRectangle(cornerRadius: 14)) }
            VStack(alignment: .leading, spacing: 8) {
                Text(article.title).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(3).multilineTextAlignment(.leading)
                HStack(spacing: 5) { Text(article.source).lineLimit(1).foregroundStyle(AppTheme.green); Text("•"); Text(article.date, style: .relative).lineLimit(1) }.font(.caption2).foregroundStyle(AppTheme.muted)
                Label("قراءة من المصدر", systemImage: "arrow.up.left").font(.caption2).foregroundStyle(AppTheme.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(14).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 20)).padding(.horizontal, 16)
    }
}
