import SwiftUI

struct V2DiscoverView: View {
    @State private var query = ""
    @State private var teams: [APIPlusTeam] = []
    @State private var players: [APIPlusPlayer] = []
    @State private var loading = false
    @State private var searched = false
    @State private var searchTask: Task<Void, Never>?
    @State private var searchGeneration = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    TopBar(title: "البحث")
                    if query.isEmpty && !searched { intro }
                    if loading { ProgressView().tint(AppTheme.green).padding(.top, 34) }
                    if !teams.isEmpty {
                        section("الأندية", count: teams.count)
                        ForEach(teams) { team in NavigationLink { V2TeamView(team: team) } label: { teamRow(team) }.buttonStyle(.plain) }
                    }
                    if !players.isEmpty {
                        section("اللاعبون", count: players.count)
                        ForEach(players) { player in NavigationLink { V2PlayerView(player: player) } label: { playerRow(player) }.buttonStyle(.plain) }
                    }
                    if searched && !loading && teams.isEmpty && players.isEmpty {
                        ContentUnavailableView("لا توجد نتائج", systemImage: "magnifyingglass", description: Text("جرّب كتابة الاسم بالإنجليزية أو جزءًا من الاسم")).padding(.top, 50)
                    }
                }.padding(.bottom, 30)
            }
            .background(AppTheme.bg.ignoresSafeArea())
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "نادي أو لاعب")
            .onChange(of: query) { _, value in scheduleSearch(value) }
            .onSubmit(of: .search) { searchTask?.cancel(); Task { await search(query) } }
            .onDisappear { searchTask?.cancel() }
        }
    }

    private var intro: some View {
        VStack(spacing: 14) {
            Image(systemName: "magnifyingglass.circle.fill").font(.system(size: 54)).foregroundStyle(AppTheme.green)
            Text("ابحث في 90+").font(.title2.bold())
            Text("ابحث عن نادي أو لاعب من قاعدة البيانات الرياضية الحقيقية، ثم ادخل إلى صفحته ومبارياته ومعلوماته.").font(.subheadline).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
            HStack(spacing: 8) { suggestion("Al Hilal"); suggestion("Al Ittihad"); suggestion("Ronaldo") }
        }.padding(22).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22)).padding(.horizontal, 16)
    }

    private func suggestion(_ text: String) -> some View {
        Button { query = text } label: {
            Text(text).font(.caption.bold()).foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 8).background(AppTheme.green.opacity(0.14), in: Capsule())
        }
    }

    private func scheduleSearch(_ value: String) {
        searchTask?.cancel()
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count < 2 {
            searchGeneration += 1
            searched = false; loading = false; teams = []; players = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await search(text)
        }
    }

    @MainActor private func search(_ raw: String) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2, APIFootballClient.isConfigured else { return }
        searchGeneration += 1
        let generation = searchGeneration
        searched = true; loading = true
        async let t = try? APISportsStore.shared.searchTeams(text)
        async let p = try? APISportsStore.shared.searchPlayers(text)
        let result = await (t, p)
        guard generation == searchGeneration, text == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        teams = result.0 ?? []; players = result.1 ?? []; loading = false
    }

    private func section(_ title: String, count: Int) -> some View { HStack { Text(title).font(.title3.bold()); Spacer(); Text("\(count)").font(.caption).foregroundStyle(AppTheme.muted) }.padding(.horizontal, 16) }
    private func teamRow(_ team: APIPlusTeam) -> some View { HStack(spacing: 12) { RemoteBadge(url: team.logo).frame(width: 52, height: 52); VStack(alignment: .leading, spacing: 4) { Text(team.name).font(.headline); Text([team.country, team.city].compactMap { $0 }.joined(separator: " • ")).font(.caption).foregroundStyle(AppTheme.muted) }; Spacer(); Image(systemName: "chevron.left").foregroundStyle(AppTheme.muted) }.foregroundStyle(.white).padding(14).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16) }
    private func playerRow(_ player: APIPlusPlayer) -> some View { HStack(spacing: 12) { RemoteBadge(url: player.photo).frame(width: 52, height: 52); VStack(alignment: .leading, spacing: 4) { Text(player.name).font(.headline); Text(player.nationality ?? "").font(.caption).foregroundStyle(AppTheme.muted) }; Spacer(); Image(systemName: "chevron.left").foregroundStyle(AppTheme.muted) }.foregroundStyle(.white).padding(14).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16) }
}

struct V2TeamView: View {
    let team: APIPlusTeam
    @State private var next: [APIPlusMatch] = []
    @State private var last: [APIPlusMatch] = []
    @State private var loading = true
    @AppStorage("favoriteTeamIDs") private var favoriteTeamIDs = ""
    private var isFavorite: Bool { Set(favoriteTeamIDs.split(separator: ",").map(String.init)).contains(team.id) }

    var body: some View {
        ScrollView { LazyVStack(spacing: 16) { hero; if loading { ProgressView().tint(AppTheme.green).padding(30) }; if !next.isEmpty { section("المباريات القادمة"); ForEach(next) { match in NavigationLink { V2MatchCenterView(match: match) } label: { APICompactMatchCard(match: match) }.buttonStyle(.plain) } }; if !last.isEmpty { section("آخر النتائج"); ForEach(last) { match in NavigationLink { V2MatchCenterView(match: match) } label: { APICompactMatchCard(match: match) }.buttonStyle(.plain) } } }.padding(.vertical, 14) }
        .background(AppTheme.bg.ignoresSafeArea()).navigationTitle(team.name).navigationBarTitleDisplayMode(.inline).task { await load() }
    }

    private var hero: some View { VStack(spacing: 12) { RemoteBadge(url: team.logo).frame(width: 96, height: 96); Text(team.name).font(.title2.bold()); Text([team.country, team.city, team.venue].compactMap { $0 }.joined(separator: " • ")).font(.subheadline).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center); if let founded = team.founded { Text("تأسس \(founded)").font(.caption).foregroundStyle(AppTheme.muted) }; Button(action: toggleFavorite) { Label(isFavorite ? "تتم المتابعة" : "متابعة النادي", systemImage: isFavorite ? "star.fill" : "star").font(.subheadline.bold()).foregroundStyle(isFavorite ? .black : .white).padding(.horizontal, 18).padding(.vertical, 10).background(isFavorite ? AppTheme.green : AppTheme.green.opacity(0.14), in: Capsule()) } }.frame(maxWidth: .infinity).padding(22).background(LinearGradient(colors: [AppTheme.card, AppTheme.green.opacity(0.10)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 24)).padding(.horizontal, 16) }
    @MainActor private func load() async { loading = true; defer { loading = false }; async let a = try? APISportsStore.shared.teamFixtures(teamID: team.id, next: true); async let b = try? APISportsStore.shared.teamFixtures(teamID: team.id, next: false); let r = await (a,b); next = r.0 ?? []; last = r.1 ?? [] }
    private func section(_ title: String) -> some View { HStack { Text(title).font(.title3.bold()); Spacer() }.padding(.horizontal, 16) }
    private func toggleFavorite() { var ids = Set(favoriteTeamIDs.split(separator: ",").map(String.init)); if ids.contains(team.id) { ids.remove(team.id) } else { ids.insert(team.id) }; favoriteTeamIDs = ids.sorted().joined(separator: ",") }
}

struct V2PlayerView: View {
    let player: APIPlusPlayer
    @AppStorage("favoritePlayerIDs") private var favoritePlayerIDs = ""
    @State private var seasonStats: [APIPlusPlayerSeasonStat] = []
    @State private var loadingStats = true
    private var isFavorite: Bool { Set(favoritePlayerIDs.split(separator: ",").map(String.init)).contains(player.id) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    RemoteBadge(url: player.photo).frame(width: 128, height: 128)
                    Text(player.name).font(.title.bold())
                    Button(action: toggleFavorite) { Label(isFavorite ? "تتم المتابعة" : "متابعة اللاعب", systemImage: isFavorite ? "star.fill" : "star").font(.subheadline.bold()).foregroundStyle(isFavorite ? .black : .white).padding(.horizontal, 18).padding(.vertical, 10).background(isFavorite ? AppTheme.green : AppTheme.green.opacity(0.14), in: Capsule()) }
                }.frame(maxWidth: .infinity).padding(22).background(LinearGradient(colors: [AppTheme.card, AppTheme.green.opacity(0.10)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 24))
                VStack(spacing: 0) { info("الجنسية", player.nationality); Divider().overlay(Color.white.opacity(0.08)); info("تاريخ الميلاد", player.birth); Divider().overlay(Color.white.opacity(0.08)); info("الطول", player.height); Divider().overlay(Color.white.opacity(0.08)); info("الوزن", player.weight) }.background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
                HStack { Text("إحصائيات الموسم").font(.title3.bold()); Spacer(); Text("\(APIFootballClient.currentSeason)").font(.caption).foregroundStyle(AppTheme.muted) }
                if loadingStats { ProgressView().tint(AppTheme.green).padding(20) }
                else if seasonStats.isEmpty { Text("لا توجد إحصائيات موسم متاحة من المصدر حاليًا").foregroundStyle(AppTheme.muted).frame(maxWidth: .infinity).padding(24).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)) }
                else { ForEach(seasonStats) { stat in statCard(stat) } }
            }.padding(16)
        }
        .background(AppTheme.bg.ignoresSafeArea()).navigationTitle("اللاعب").navigationBarTitleDisplayMode(.inline)
        .task { seasonStats = (try? await APISportsStore.shared.playerSeasonStats(playerID: player.id)) ?? []; loadingStats = false }
    }

    private func statCard(_ stat: APIPlusPlayerSeasonStat) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) { RemoteBadge(url: stat.teamLogo).frame(width: 38, height: 38); VStack(alignment: .leading) { Text(stat.team).bold(); Text(stat.league).font(.caption).foregroundStyle(AppTheme.muted) }; Spacer(); if let rating = stat.rating, !rating.isEmpty { Text(rating).font(.headline).foregroundStyle(AppTheme.green) } }
            HStack { metric("مباريات", stat.appearances); metric("دقائق", stat.minutes); metric("أهداف", stat.goals); metric("تمريرات", stat.assists) }
            if stat.yellowCards > 0 || stat.redCards > 0 { HStack { Text("بطاقات").foregroundStyle(AppTheme.muted); Spacer(); Text("🟨 \(stat.yellowCards)   🟥 \(stat.redCards)").bold() } }
        }.padding(14).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }
    private func metric(_ title: String, _ value: Int) -> some View { VStack(spacing: 3) { Text("\(value)").font(.headline.bold()); Text(title).font(.caption2).foregroundStyle(AppTheme.muted) }.frame(maxWidth: .infinity) }
    private func info(_ title: String, _ value: String?) -> some View { HStack { Text(title).foregroundStyle(AppTheme.muted); Spacer(); Text(value ?? "—").bold() }.padding(14) }
    private func toggleFavorite() { var ids = Set(favoritePlayerIDs.split(separator: ",").map(String.init)); if ids.contains(player.id) { ids.remove(player.id) } else { ids.insert(player.id) }; favoritePlayerIDs = ids.sorted().joined(separator: ",") }
}
