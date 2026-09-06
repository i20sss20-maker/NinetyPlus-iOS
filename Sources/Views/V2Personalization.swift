import SwiftUI

struct V2FavoritesView: View {
    @AppStorage("favoriteTeamIDs") private var favoriteTeamIDs = ""
    @AppStorage("favoritePlayerIDs") private var favoritePlayerIDs = ""
    @State private var teams: [APIPlusTeam] = []
    @State private var players: [APIPlusPlayer] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                TopBar(title: "المتابعة")
                if loading { ProgressView().tint(AppTheme.green).padding(30) }
                if !teams.isEmpty {
                    header("الأندية", teams.count)
                    ForEach(teams) { team in
                        NavigationLink { V2TeamView(team: team) } label: {
                            HStack(spacing: 12) {
                                RemoteBadge(url: team.logo).frame(width: 48, height: 48)
                                VStack(alignment: .leading) {
                                    Text(team.name).font(.headline)
                                    Text(team.country ?? "").font(.caption).foregroundStyle(AppTheme.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.left").foregroundStyle(AppTheme.muted)
                            }
                            .foregroundStyle(.white)
                            .padding(14)
                            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
                            .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !players.isEmpty {
                    header("اللاعبون", players.count)
                    ForEach(players) { player in
                        NavigationLink { V2PlayerView(player: player) } label: {
                            HStack(spacing: 12) {
                                RemoteBadge(url: player.photo).frame(width: 48, height: 48)
                                VStack(alignment: .leading) {
                                    Text(player.name).font(.headline)
                                    Text(player.nationality ?? "").font(.caption).foregroundStyle(AppTheme.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.left").foregroundStyle(AppTheme.muted)
                            }
                            .foregroundStyle(.white)
                            .padding(14)
                            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
                            .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !loading && teams.isEmpty && players.isEmpty {
                    ContentUnavailableView("ما تتابع أحد للحين", systemImage: "star", description: Text("تابع نادي أو لاعب وبيظهر هنا مباشرة"))
                        .padding(.top, 60)
                }
            }
            .padding(.bottom, 30)
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .task { await load() }
        .refreshable { await load() }
    }

    private func header(_ title: String, _ count: Int) -> some View {
        HStack {
            Text(title).font(.title3.bold())
            Spacer()
            Text("\(count)").font(.caption).foregroundStyle(AppTheme.muted)
        }
        .padding(.horizontal, 16)
    }

    @MainActor private func load() async {
        loading = true
        defer { loading = false }
        let teamIDs = favoriteTeamIDs.split(separator: ",").map(String.init)
        let playerIDs = favoritePlayerIDs.split(separator: ",").map(String.init)
        var loadedTeams: [APIPlusTeam] = []
        var loadedPlayers: [APIPlusPlayer] = []

        for id in teamIDs {
            if let team = try? await APISportsStore.shared.team(id: id) { loadedTeams.append(team) }
        }
        for id in playerIDs {
            if let player = try? await APISportsStore.shared.player(id: id) { loadedPlayers.append(player) }
        }

        teams = loadedTeams
        players = loadedPlayers
    }
}

struct V2LeaguesListView: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                TopBar(title: "البطولات")
                ForEach(LeagueOption.featured) { league in
                    NavigationLink { V2LeagueHubView(league: league) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "trophy.fill")
                                .foregroundStyle(AppTheme.green)
                                .frame(width: 42, height: 42)
                                .background(AppTheme.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading) {
                                Text(league.arabicName).font(.headline)
                                Text(league.englishName).font(.caption).foregroundStyle(AppTheme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.left").foregroundStyle(AppTheme.muted)
                        }
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 30)
        }
        .background(AppTheme.bg.ignoresSafeArea())
    }
}

struct V2MoreView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    TopBar(title: "المزيد")
                    NavigationLink { V2FavoritesView() } label: { card("المتابعة", "أنديتك ولاعبوك المفضلون", "star.fill") }
                    NavigationLink { V2LeaguesListView() } label: { card("البطولات", "الترتيب والمباريات والهدافون", "trophy.fill") }
                    NavigationLink { EnhancedTransfersView() } label: { card("الانتقالات", "آخر أخبار سوق الانتقالات", "arrow.left.arrow.right") }
                    NavigationLink { V2DiscoverView() } label: { card("البحث", "ابحث عن نادي أو لاعب", "magnifyingglass") }
                    statusCard
                }
                .padding(.bottom, 30)
            }
            .background(AppTheme.bg.ignoresSafeArea())
        }
    }

    private var statusCard: some View {
        HStack(spacing: 14) {
            Image(systemName: APIFootballClient.isConfigured ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(APIFootballClient.isConfigured ? AppTheme.green : .orange)
                .frame(width: 48, height: 48)
                .background((APIFootballClient.isConfigured ? AppTheme.green : Color.orange).opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text("حالة الخدمة").font(.headline).foregroundStyle(.white)
                Text(APIFootballClient.isConfigured ? "متصل بمصدر البيانات" : "الخدمة الرياضية غير متاحة حاليًا")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            Spacer()
        }
        .padding(14)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 16)
    }

    private func card(_ title: String, _ subtitle: String, _ icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(AppTheme.green)
                .frame(width: 48, height: 48)
                .background(AppTheme.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(.white)
                Text(subtitle).font(.caption).foregroundStyle(AppTheme.muted)
            }
            Spacer()
            Image(systemName: "chevron.left").foregroundStyle(AppTheme.muted)
        }
        .padding(14)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 16)
    }
}
