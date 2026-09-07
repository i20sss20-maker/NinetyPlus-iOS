import SwiftUI

struct V2FavoritesView: View {
    @AppStorage("favoriteTeamIDs") private var favoriteTeamIDs = ""
    @AppStorage("favoritePlayerIDs") private var favoritePlayerIDs = ""
    @State private var resource = PageResource<FavoriteSnapshot>()
    @State private var retryID = 0

    private struct FavoriteSnapshot {
        var teams: [APIPlusTeam] = []
        var players: [APIPlusPlayer] = []
    }
    private enum FavoriteRequest {
        case team(String), player(String)
    }
    private enum FavoriteOutcome {
        case team(APIPlusTeam), player(APIPlusPlayer), missing, failure(String)
    }

    private var teamIDs: [String] { SavedFavoriteIDs.parse(favoriteTeamIDs) }
    private var playerIDs: [String] { SavedFavoriteIDs.parse(favoritePlayerIDs) }
    private var selectionKey: String { "teams:\(teamIDs.joined(separator: ","))|players:\(playerIDs.joined(separator: ","))" }
    private var hasSavedFavorites: Bool { !teamIDs.isEmpty || !playerIDs.isEmpty }
    // Removed follows disappear immediately, even while an older fetch is pending.
    private var teams: [APIPlusTeam] {
        let selected = Set(teamIDs)
        return (resource.value?.teams ?? []).filter { selected.contains($0.id) }
    }
    private var players: [APIPlusPlayer] {
        let selected = Set(playerIDs)
        return (resource.value?.players ?? []).filter { selected.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                TopBar(title: "المتابعة")
                if !hasSavedFavorites {
                    ContentUnavailableView("ما تتابع أحد للحين", systemImage: "star", description: Text("تابع نادي أو لاعب وبيظهر هنا مباشرة"))
                        .padding(.top, 30)
                    NavigationLink { V2DiscoverView() } label: {
                        Label("ابحث عن نادي أو لاعب", systemImage: "magnifyingglass")
                            .font(.subheadline.bold()).foregroundStyle(AppTheme.green)
                    }
                } else {
                    PageLoadFeedback(
                        loading: resource.isLoading || resource.key != selectionKey,
                        hasValue: !teams.isEmpty || !players.isEmpty,
                        message: resource.key == selectionKey ? resource.errorMessage : nil,
                        updatedAt: resource.key == selectionKey ? resource.lastUpdated : nil
                    ) { retryID += 1 }
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
                                .foregroundStyle(.white).padding(14)
                                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
                            }.buttonStyle(.plain)
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
                                .foregroundStyle(.white).padding(14)
                                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }.padding(.bottom, 30)
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .task(id: "\(selectionKey)|\(retryID)") { await load() }
        .refreshable { await load(force: true) }
        .onDisappear { resource.invalidate() }
    }

    private func header(_ title: String, _ count: Int) -> some View {
        HStack {
            Text(title).font(.title3.bold())
            Spacer()
            Text("\(count)").font(.caption).foregroundStyle(AppTheme.muted)
        }.padding(.horizontal, 16)
    }

    @MainActor private func load(force: Bool = false) async {
        guard !Task.isCancelled else { return }
        let key = selectionKey
        if !force && resource.isFresh(key: key, maxAge: 180) { return }
        let selectedTeams = teamIDs
        let selectedPlayers = playerIDs
        var knownTeams = Dictionary(teams.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var knownPlayers = Dictionary(players.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let token = resource.begin(key: key, retainingValue: true)
        defer { resource.cancel(token: token) }
        let requests = selectedTeams.map { FavoriteRequest.team($0) } + selectedPlayers.map { FavoriteRequest.player($0) }
        guard !requests.isEmpty else {
            resource.succeed(FavoriteSnapshot(), token: token)
            return
        }

        var successes = 0
        var failures = 0
        var firstError: String?
        // At most four lookups at once. Results are applied back on the main actor.
        for start in stride(from: 0, to: requests.count, by: 4) {
            guard !Task.isCancelled, selectionKey == key else { return }
            let batch = Array(requests[start..<min(start + 4, requests.count)])
            let outcomes = await withTaskGroup(of: FavoriteOutcome.self) { group in
                for request in batch {
                    group.addTask { await Self.fetch(request) }
                }
                var results: [FavoriteOutcome] = []
                for await result in group { results.append(result) }
                return results
            }
            guard !Task.isCancelled, selectionKey == key else { return }
            for outcome in outcomes {
                switch outcome {
                case .team(let team): knownTeams[team.id] = team; successes += 1
                case .player(let player): knownPlayers[player.id] = player; successes += 1
                case .missing: failures += 1
                case .failure(let message): failures += 1; if firstError == nil { firstError = message }
                }
            }
        }
        guard !Task.isCancelled, selectionKey == key else { return }
        let snapshot = FavoriteSnapshot(
            teams: selectedTeams.compactMap { knownTeams[$0] },
            players: selectedPlayers.compactMap { knownPlayers[$0] }
        )
        let warning: String? = failures == 0 ? nil : "لم تكتمل بيانات \(failures) من متابعاتك. \(firstError ?? "بعض الملفات غير متاحة من المصدر حاليًا.") اختياراتك محفوظة ولم يتم حذفها."
        if successes == 0 {
            resource.fail(warning ?? "تعذر تحميل المتابعات حاليًا. اختياراتك محفوظة.", token: token)
        } else {
            resource.succeed(snapshot, token: token, warning: warning)
        }
    }

    private static func fetch(_ request: FavoriteRequest) async -> FavoriteOutcome {
        do {
            try Task.checkCancellation()
            switch request {
            case .team(let id):
                if let value = try await APISportsStore.shared.team(id: id) { return .team(value) }
            case .player(let id):
                if let value = try await APISportsStore.shared.player(id: id) { return .player(value) }
            }
            return .missing
        } catch {
            return .failure(error.localizedDescription)
        }
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
    @State private var health: NinetyPlusBackendHealth?
    @State private var healthLoading = true
    @State private var healthError = false

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
            .task { await refreshHealth() }
            .refreshable { await refreshHealth() }
        }
    }

    private var isHealthy: Bool { health?.ok == true && health?.providerConfigured != false && !healthError }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                if healthLoading {
                    ProgressView().tint(AppTheme.green).frame(width: 48, height: 48)
                } else {
                    Image(systemName: isHealthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(isHealthy ? AppTheme.green : .orange)
                        .frame(width: 48, height: 48)
                        .background((isHealthy ? AppTheme.green : Color.orange).opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("حالة الخدمة").font(.headline).foregroundStyle(.white)
                    Text(healthLoading ? "جاري التحقق من الاتصال..." : (isHealthy ? "الخدمة متصلة وتعمل بشكل طبيعي" : "تعذر الاتصال بالخدمة مؤقتًا"))
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
            }

            if !healthLoading && !isHealthy {
                Divider().overlay(Color.white.opacity(0.08))
                Text("قد تستمر بعض الصفحات بعرض آخر بيانات محفوظة حتى يعود الاتصال.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .padding(14)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 16)
    }

    @MainActor private func refreshHealth() async {
        healthLoading = true
        defer { healthLoading = false }
        do {
            health = try await APIFootballClient.health()
            healthError = false
        } catch {
            health = nil
            healthError = true
        }
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
