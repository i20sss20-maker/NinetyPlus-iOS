import SwiftUI

struct V2HomeView: View {
    @StateObject private var api = APISportsStore.shared
    @StateObject private var content = EditorialStore.shared
    @AppStorage("favoriteTeamIDs") private var favoriteTeamIDs = ""
    @AppStorage("favoritePlayerIDs") private var favoritePlayerIDs = ""
    @State private var favoriteUpcoming: [APIPlusMatch] = []
    @State private var loadingFavorites = false

    private var live: [APIPlusMatch] { api.today.filter { api.isLive($0.status) } }
    private var favoriteTeams: Set<String> { Set(favoriteTeamIDs.split(separator: ",").map(String.init)) }
    private var favoritePlayersCount: Int { favoritePlayerIDs.split(separator: ",").count }
    private var personalizedMatches: [APIPlusMatch] {
        guard !favoriteTeams.isEmpty else { return [] }
        return api.today.filter { match in
            if let homeID = match.homeID, favoriteTeams.contains(homeID) { return true }
            if let awayID = match.awayID, favoriteTeams.contains(awayID) { return true }
            return false
        }
    }
    private var forYouMatches: [APIPlusMatch] {
        var seen = Set<String>()
        return (personalizedMatches + favoriteUpcoming).filter { seen.insert($0.id).inserted }.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    TopBar(title: nil, showsLogo: true)
                    if !APIFootballClient.isConfigured { serviceUnavailableCard } else {
                        liveHero
                        forYouSection
                        todaySection
                        quickActions
                        newsSection
                    }
                }.padding(.bottom, 28)
            }
            .background(AppTheme.bg.ignoresSafeArea())
            .refreshable {
                async let a: Void = api.refreshToday(force: true)
                async let b: Void = content.refresh()
                async let c: Void = loadFavoriteUpcoming(force: true)
                _ = await (a, b, c)
            }
            .task {
                async let a: Void = api.refreshToday()
                async let b: Void = content.refreshIfStale(maxAge: 180)
                async let c: Void = loadFavoriteUpcoming()
                _ = await (a, b, c)
            }
            .onChange(of: favoriteTeamIDs) { _, _ in Task { await loadFavoriteUpcoming(force: true) } }
        }
    }

    @ViewBuilder private var liveHero: some View {
        if let match = live.first ?? api.today.first {
            NavigationLink { V2MatchCenterView(match: match) } label: {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label(live.isEmpty ? "أبرز مباراة" : "مباشر الآن", systemImage: live.isEmpty ? "star.fill" : "dot.radiowaves.left.and.right")
                            .font(.caption.bold()).foregroundStyle(live.isEmpty ? AppTheme.muted : AppTheme.green)
                        Spacer(); Text(match.league).font(.caption).foregroundStyle(AppTheme.muted).lineLimit(1)
                    }
                    HStack(spacing: 14) {
                        heroTeam(match.home, match.homeLogo); Spacer()
                        VStack(spacing: 5) {
                            if let h = match.homeScore, let a = match.awayScore { Text("\(h) - \(a)").font(.system(size: 31, weight: .black, design: .rounded)) }
                            else if let date = match.date { Text(date, style: .time).font(.title2.bold()) }
                            Text(statusArabic(match.status, elapsed: match.elapsed)).font(.caption.bold()).foregroundStyle(AppTheme.green)
                        }
                        Spacer(); heroTeam(match.away, match.awayLogo)
                    }
                }
                .foregroundStyle(.white).padding(18)
                .background(LinearGradient(colors: [AppTheme.card, AppTheme.green.opacity(0.12)], startPoint: .topTrailing, endPoint: .bottomLeading), in: RoundedRectangle(cornerRadius: 24))
                .padding(.horizontal, 16)
            }.buttonStyle(.plain)
        }
    }

    @ViewBuilder private var forYouSection: some View {
        if favoriteTeams.isEmpty && favoritePlayersCount == 0 {
            VStack(spacing: 10) {
                sectionHeader("لك", subtitle: "خصص تجربتك")
                NavigationLink { V2FavoritesView() } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "star.circle.fill").font(.system(size: 34)).foregroundStyle(AppTheme.green)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("خل 90+ يعرف اهتماماتك").font(.headline).foregroundStyle(.white)
                            Text("تابع أنديتك ولاعبيك وبتظهر مبارياتهم ومحتواهم هنا تلقائيًا.").font(.caption).foregroundStyle(AppTheme.muted).multilineTextAlignment(.leading)
                        }
                        Spacer(); Image(systemName: "chevron.left").foregroundStyle(AppTheme.muted)
                    }
                    .padding(16).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20)).padding(.horizontal, 16)
                }.buttonStyle(.plain)
            }
        } else {
            VStack(spacing: 10) {
                sectionHeader("لك", subtitle: "\(favoriteTeams.count) نادي • \(favoritePlayersCount) لاعب")
                if loadingFavorites && forYouMatches.isEmpty {
                    ProgressView("جاري تجهيز مباريات متابعاتك...").tint(AppTheme.green).font(.caption).padding(22)
                } else if forYouMatches.isEmpty {
                    NavigationLink { V2FavoritesView() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "star.fill").foregroundStyle(AppTheme.green)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("متابعاتك محفوظة").font(.subheadline.bold()).foregroundStyle(.white)
                                Text("لا توجد مباراة قريبة للأندية التي تتابعها حاليًا. افتح مركز المتابعة لرؤية أنديتك ولاعبيك.").font(.caption).foregroundStyle(AppTheme.muted).multilineTextAlignment(.leading)
                            }
                            Spacer(); Image(systemName: "chevron.left").foregroundStyle(AppTheme.muted)
                        }
                        .padding(14).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
                    }.buttonStyle(.plain)
                } else {
                    ForEach(forYouMatches.prefix(6)) { match in
                        NavigationLink { V2MatchCenterView(match: match) } label: { APICompactMatchCard(match: match) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var todaySection: some View {
        VStack(spacing: 10) {
            sectionHeader("مباريات اليوم", subtitle: "\(api.today.count) مباراة")
            if api.loading && api.today.isEmpty { ProgressView().tint(AppTheme.green).padding(30) }
            else if api.today.isEmpty { emptyCard("لا توجد مباريات متاحة اليوم", icon: "soccerball") }
            else { ForEach(Array(api.today.prefix(6))) { match in NavigationLink { V2MatchCenterView(match: match) } label: { APICompactMatchCard(match: match) }.buttonStyle(.plain) } }
        }
    }

    private var quickActions: some View {
        VStack(spacing: 10) {
            sectionHeader("استكشف 90+", subtitle: nil)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    NavigationLink { V2DiscoverView() } label: { quickCard("بحث", icon: "magnifyingglass") }
                    NavigationLink { V2LeagueHubView(league: LeagueOption.featured[0]) } label: { quickCard("الدوري السعودي", icon: "list.number") }
                    NavigationLink { V2FavoritesView() } label: { quickCard("لك", icon: "star.fill") }
                    NavigationLink { EnhancedTransfersView() } label: { quickCard("الانتقالات", icon: "arrow.left.arrow.right") }
                    NavigationLink { V2MatchesView() } label: { quickCard("كل المباريات", icon: "calendar") }
                }.padding(.horizontal, 16)
            }.buttonStyle(.plain)
        }
    }

    private var newsSection: some View {
        VStack(spacing: 10) {
            sectionHeader("آخر الأخبار", subtitle: "مصادر حقيقية")
            if content.news.isEmpty { emptyCard("جاري جلب آخر الأخبار", icon: "newspaper") }
            else {
                ForEach(Array(content.news.prefix(4))) { article in
                    if let url = article.url {
                        Link(destination: url) {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 12).fill(AppTheme.green.opacity(0.12)).frame(width: 52, height: 52).overlay { Image(systemName: "newspaper.fill").foregroundStyle(AppTheme.green) }
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(article.title).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(2)
                                    HStack(spacing: 6) { Text(article.source); Text("•"); Text(article.date, style: .relative) }.font(.caption2).foregroundStyle(AppTheme.muted)
                                }
                                Spacer(minLength: 0)
                            }.padding(12).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
    }

    @MainActor private func loadFavoriteUpcoming(force: Bool = false) async {
        guard APIFootballClient.isConfigured else { return }
        let ids = Array(favoriteTeams.prefix(6))
        guard !ids.isEmpty else { favoriteUpcoming = []; return }
        if !force, !favoriteUpcoming.isEmpty { return }
        loadingFavorites = true
        defer { loadingFavorites = false }
        var combined: [APIPlusMatch] = []
        for id in ids {
            let items = (try? await APISportsStore.shared.teamFixtures(teamID: id, next: true)) ?? []
            combined.append(contentsOf: items.prefix(3))
        }
        var seen = Set<String>()
        favoriteUpcoming = combined.filter { seen.insert($0.id).inserted }.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    private var serviceUnavailableCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 46)).foregroundStyle(AppTheme.green)
            Text("تعذر الاتصال بخدمة البيانات").font(.title2.bold())
            Text("تحقق من اتصال الإنترنت وحاول التحديث بعد قليل.").font(.subheadline).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
        }
        .padding(24).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 24)).padding(.horizontal, 16)
    }

    private func sectionHeader(_ title: String, subtitle: String?) -> some View { HStack(alignment: .firstTextBaseline) { Text(title).font(.title3.bold()); Spacer(); if let subtitle { Text(subtitle).font(.caption).foregroundStyle(AppTheme.muted) } }.padding(.horizontal, 16) }
    private func heroTeam(_ name: String, _ logo: String?) -> some View { VStack(spacing: 7) { RemoteBadge(url: logo).frame(width: 64, height: 64); Text(name).font(.subheadline.bold()).multilineTextAlignment(.center).lineLimit(2).frame(width: 100) } }
    private func quickCard(_ title: String, icon: String) -> some View { VStack(spacing: 9) { Image(systemName: icon).font(.title2.bold()).foregroundStyle(AppTheme.green); Text(title).font(.caption.bold()).foregroundStyle(.white).lineLimit(1) }.frame(width: 112, height: 88).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)) }
    private func emptyCard(_ text: String, icon: String) -> some View { Label(text, systemImage: icon).font(.subheadline).foregroundStyle(AppTheme.muted).frame(maxWidth: .infinity).padding(22).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16) }
    private func statusArabic(_ status: String, elapsed: Int?) -> String { let s=status.uppercased(); if api.isLive(s) { return elapsed.map { "مباشر • \($0)′" } ?? "مباشر" }; switch s { case "FT": return "انتهت"; case "HT": return "بين الشوطين"; case "NS": return "لم تبدأ"; case "PST": return "مؤجلة"; case "CANC": return "ملغاة"; case "AET": return "انتهت بعد وقت إضافي"; case "PEN": return "انتهت بركلات الترجيح"; default: return status.isEmpty ? "موعد" : status } }
}
