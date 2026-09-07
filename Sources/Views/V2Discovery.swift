import SwiftUI

struct V2DiscoverView: View {
    @State private var query = ""
    @State private var teams: [APIPlusTeam] = []
    @State private var players: [APIPlusPlayer] = []
    @State private var loading = false
    @State private var searched = false
    @State private var warning: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var searchGeneration = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    TopBar(title: "البحث", subtitle: "أندية ولاعبون من قاعدة البيانات")
                    if query.isEmpty && !searched { intro }
                    if loading && teams.isEmpty && players.isEmpty {
                        VStack(spacing: 12) {
                            ProgressView().tint(AppTheme.green)
                            Text("جاري البحث...").font(.caption).foregroundStyle(AppTheme.muted)
                        }.padding(.top, 38)
                    }
                    if let warning, !loading { errorCard(warning) }
                    if !teams.isEmpty {
                        section("الأندية", count: teams.count)
                        ForEach(teams) { team in
                            NavigationLink { V2TeamView(team: team) } label: { teamRow(team) }
                                .buttonStyle(.plain)
                        }
                    }
                    if !players.isEmpty {
                        section("اللاعبون", count: players.count)
                        ForEach(players) { player in
                            NavigationLink { V2PlayerView(player: player) } label: { playerRow(player) }
                                .buttonStyle(.plain)
                        }
                    }
                    if searched && !loading && warning == nil && teams.isEmpty && players.isEmpty {
                        ContentUnavailableView(
                            "لا توجد نتائج",
                            systemImage: "magnifyingglass",
                            description: Text("جرّب الاسم بالعربية أو الإنجليزية، أو اكتب جزءًا من الاسم.")
                        ).padding(.top, 48)
                    }
                }.padding(.bottom, 32)
            }
            .background(AppTheme.bg.ignoresSafeArea())
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "مثال: الهلال، الاتحاد، رونالدو")
            .onChange(of: query) { _, value in scheduleSearch(value) }
            .onSubmit(of: .search) { searchTask?.cancel(); Task { await search(query) } }
            .onDisappear { searchTask?.cancel() }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(AppTheme.green.opacity(0.14))
                    Image(systemName: "magnifyingglass").font(.system(size: 26, weight: .bold)).foregroundStyle(AppTheme.green)
                }.frame(width: 62, height: 62)
                VStack(alignment: .leading, spacing: 4) {
                    Text("ابحث عن فريقك أو لاعبك").font(.title3.bold())
                    Text("اكتب الاسم بالعربية أو الإنجليزية").font(.subheadline).foregroundStyle(AppTheme.muted)
                }
            }
            Text("نتائج البحث تفتح صفحات حقيقية للأندية واللاعبين، مع المباريات والإحصائيات المتاحة من المصدر.")
                .font(.subheadline).foregroundStyle(AppTheme.muted).fixedSize(horizontal: false, vertical: true)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    suggestion("الهلال")
                    suggestion("الاتحاد")
                    suggestion("النصر")
                    suggestion("رونالدو")
                }
            }
        }
        .padding(18)
        .background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(AppTheme.border, lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private func suggestion(_ text: String) -> some View {
        Button { query = text } label: {
            Text(text).font(.caption.bold()).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(AppTheme.soft, in: Capsule())
                .overlay(Capsule().stroke(AppTheme.border, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private func errorCard(_ message: String) -> some View {
        RetryStateCard(title: teams.isEmpty && players.isEmpty ? "تعذر إكمال البحث" : "وصلت بعض النتائج فقط", message: message) {
            Task { await search(query) }
        }
    }

    private func scheduleSearch(_ value: String) {
        searchTask?.cancel()
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count < 2 {
            searchGeneration += 1
            searched = false; loading = false; warning = nil; teams = []; players = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(380))
            guard !Task.isCancelled else { return }
            await search(text)
        }
    }

    @MainActor private func search(_ raw: String) async {
        let entered = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard entered.count >= 2 else { return }
        guard APIFootballClient.isConfigured else {
            searched = true; warning = "خدمة البيانات غير متاحة حاليًا."; teams = []; players = []
            return
        }

        let providerQuery = providerSearchText(entered)
        searchGeneration += 1
        let generation = searchGeneration
        searched = true; loading = true; warning = nil

        async let teamResult = capture { try await APISportsStore.shared.searchTeams(providerQuery) }
        async let playerResult = capture { try await APISportsStore.shared.searchPlayers(providerQuery) }
        let result = await (teamResult, playerResult)

        guard generation == searchGeneration,
              entered == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }

        loading = false
        teams = result.0.value ?? []
        players = result.1.value ?? []
        let errors = [result.0.error, result.1.error].compactMap { $0 }
        if !errors.isEmpty {
            warning = errors.count == 2 ? errors[0] : "تعذر تحميل جزء من نتائج البحث. النتائج التي وصلت ما زالت معروضة."
        }
    }

    private func capture<T>(_ operation: @escaping () async throws -> T) async -> (value: T?, error: String?) {
        do { return (try await operation(), nil) }
        catch { return (nil, error.localizedDescription) }
    }

    private func providerSearchText(_ raw: String) -> String {
        let key = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let map: [String: String] = [
            "الهلال": "Al Hilal", "الاتحاد": "Al Ittihad", "النصر": "Al Nassr", "الأهلي": "Al Ahli",
            "الشباب": "Al Shabab", "القادسية": "Al Qadisiyah", "الاتفاق": "Al Ettifaq",
            "رونالدو": "Ronaldo", "كريستيانو": "Cristiano Ronaldo", "ميسي": "Messi", "نيمار": "Neymar"
        ]
        return map[key] ?? raw
    }

    private func section(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).font(.title3.bold())
            Spacer()
            Text("\(count) نتيجة").font(.caption).foregroundStyle(AppTheme.muted)
        }.padding(.horizontal, 16)
    }

    private func teamRow(_ team: APIPlusTeam) -> some View {
        HStack(spacing: 13) {
            RemoteBadge(url: team.logo).frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 5) {
                Text(SportsArabic.team(team.name)).font(.headline).foregroundStyle(.white)
                Text([SportsArabic.country(team.country), team.city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " • "))
                    .font(.caption).foregroundStyle(AppTheme.muted).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.left").font(.caption.bold()).foregroundStyle(AppTheme.dimmed)
        }
        .padding(14)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(AppTheme.border, lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private func playerRow(_ player: APIPlusPlayer) -> some View {
        HStack(spacing: 13) {
            PlayerPortrait(url: player.photo, size: 58)
            VStack(alignment: .leading, spacing: 5) {
                Text(player.name).font(.headline).foregroundStyle(.white)
                if let nation = SportsArabic.country(player.nationality), !nation.isEmpty {
                    Text(nation).font(.caption).foregroundStyle(AppTheme.muted)
                }
            }
            Spacer()
            Image(systemName: "chevron.left").font(.caption.bold()).foregroundStyle(AppTheme.dimmed)
        }
        .padding(14)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(AppTheme.border, lineWidth: 1))
        .padding(.horizontal, 16)
    }
}

private struct RetryStateCard: View {
    let title: String
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath").font(.system(size: 32)).foregroundStyle(.orange)
            Text(title).font(.headline)
            Text(message).font(.caption).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
            Button(action: retry) {
                Label("إعادة المحاولة", systemImage: "arrow.clockwise")
                    .font(.subheadline.bold()).foregroundStyle(.black)
                    .padding(.horizontal, 17).padding(.vertical, 10)
                    .background(AppTheme.green, in: Capsule())
            }.buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity).padding(20)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(AppTheme.border, lineWidth: 1))
        .padding(.horizontal, 16)
    }
}

private struct PlayerPortrait: View {
    let url: String?
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(AppTheme.cardRaised)
            if let raw = url, let imageURL = URL(string: raw) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .empty: ProgressView().tint(AppTheme.green).scaleEffect(0.7)
                    default: fallback
                    }
                }
            } else { fallback }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(AppTheme.border, lineWidth: 1))
    }

    private var fallback: some View {
        Image(systemName: "person.fill").font(.system(size: size * 0.38)).foregroundStyle(AppTheme.dimmed)
    }
}

struct V2TeamView: View {
    let team: APIPlusTeam
    @State private var next: [APIPlusMatch] = []
    @State private var last: [APIPlusMatch] = []
    @State private var loading = true
    @State private var loadWarning: String?
    @AppStorage("favoriteTeamIDs") private var favoriteTeamIDs = ""

    private var isFavorite: Bool { SavedFavoriteIDs.parse(favoriteTeamIDs).contains(team.id) }
    private var displayName: String { SportsArabic.team(team.name) }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                hero
                if loading && next.isEmpty && last.isEmpty { ProgressView().tint(AppTheme.green).padding(30) }
                if let loadWarning { RetryStateCard(title: next.isEmpty && last.isEmpty ? "تعذر تحميل مباريات النادي" : "بعض بيانات النادي لم تصل", message: loadWarning) { Task { await load() } } }
                if !next.isEmpty {
                    section("المباريات القادمة")
                    ForEach(next) { match in NavigationLink { V2MatchCenterView(match: match) } label: { APICompactMatchCard(match: match) }.buttonStyle(.plain) }
                }
                if !last.isEmpty {
                    section("آخر النتائج")
                    ForEach(last) { match in NavigationLink { V2MatchCenterView(match: match) } label: { APICompactMatchCard(match: match) }.buttonStyle(.plain) }
                }
                if !loading && loadWarning == nil && next.isEmpty && last.isEmpty {
                    ContentUnavailableView("لا توجد مباريات منشورة", systemImage: "soccerball", description: Text("لا توجد مباريات قادمة أو نتائج حديثة متاحة لهذا النادي حاليًا."))
                        .padding(.horizontal, 16)
                }
            }.padding(.vertical, 14)
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .navigationTitle(displayName).navigationBarTitleDisplayMode(.inline)
        .task { await load() }.refreshable { await load() }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                RemoteBadge(url: team.logo).frame(width: 90, height: 90)
                VStack(alignment: .leading, spacing: 6) {
                    Text(displayName).font(.system(size: 27, weight: .bold, design: .rounded))
                    let details = [SportsArabic.country(team.country), team.city].compactMap { $0 }.filter { !$0.isEmpty }
                    if !details.isEmpty { Text(details.joined(separator: " • ")).font(.subheadline).foregroundStyle(AppTheme.muted) }
                    if let founded = team.founded { Text("تأسس عام \(founded)").font(.caption).foregroundStyle(AppTheme.dimmed) }
                }
                Spacer(minLength: 0)
            }
            if let venue = team.venue, !venue.isEmpty {
                HStack { Image(systemName: "sportscourt").foregroundStyle(AppTheme.green); Text(venue).font(.caption); Spacer() }
                    .foregroundStyle(AppTheme.muted)
            }
            Button(action: toggleFavorite) {
                Label(isFavorite ? "تتم متابعة النادي" : "متابعة النادي", systemImage: isFavorite ? "star.fill" : "star")
                    .font(.subheadline.bold()).foregroundStyle(isFavorite ? .black : .white)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(isFavorite ? AppTheme.green : AppTheme.soft, in: RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain)
        }
        .padding(18)
        .background(LinearGradient(colors: [AppTheme.cardRaised, AppTheme.greenDeep.opacity(0.34)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(AppTheme.border, lineWidth: 1))
        .padding(.horizontal, 16)
    }

    @MainActor private func load() async {
        loading = true; loadWarning = nil
        async let upcoming = capture { try await APISportsStore.shared.teamFixtures(teamID: team.id, next: true) }
        async let recent = capture { try await APISportsStore.shared.teamFixtures(teamID: team.id, next: false) }
        let result = await (upcoming, recent)
        if let value = result.0.value { next = value }
        if let value = result.1.value { last = value }
        let errors = [result.0.error, result.1.error].compactMap { $0 }
        if !errors.isEmpty { loadWarning = errors.count == 2 ? errors[0] : "تعذر تحميل جزء من المباريات. البيانات التي وصلت ما زالت معروضة." }
        loading = false
    }

    private func capture<T>(_ operation: @escaping () async throws -> T) async -> (value: T?, error: String?) {
        do { return (try await operation(), nil) } catch { return (nil, error.localizedDescription) }
    }

    private func section(_ title: String) -> some View { HStack { Text(title).font(.title3.bold()); Spacer() }.padding(.horizontal, 16) }
    private func toggleFavorite() {
        var ids = Set(SavedFavoriteIDs.parse(favoriteTeamIDs))
        if ids.contains(team.id) { ids.remove(team.id) } else { ids.insert(team.id) }
        favoriteTeamIDs = ids.sorted().joined(separator: ",")
    }
}

struct V2PlayerView: View {
    let player: APIPlusPlayer
    @AppStorage("favoritePlayerIDs") private var favoritePlayerIDs = ""
    @State private var seasonStats: [APIPlusPlayerSeasonStat] = []
    @State private var loadingStats = true
    @State private var statsError: String?

    private var isFavorite: Bool { SavedFavoriteIDs.parse(favoritePlayerIDs).contains(player.id) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero
                infoCard
                HStack {
                    Text("إحصائيات الموسم").font(.title3.bold())
                    Spacer()
                    Text("موسم \(APIFootballClient.currentSeason)").font(.caption).foregroundStyle(AppTheme.muted)
                }
                if loadingStats && seasonStats.isEmpty { ProgressView().tint(AppTheme.green).padding(20) }
                if let statsError { RetryStateCard(title: "تعذر تحميل إحصائيات اللاعب", message: statsError) { Task { await loadStats() } } }
                if !loadingStats && statsError == nil && seasonStats.isEmpty {
                    Text("لا توجد إحصائيات منشورة لهذا اللاعب في الموسم الحالي.")
                        .foregroundStyle(AppTheme.muted).frame(maxWidth: .infinity).padding(24)
                        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
                }
                ForEach(seasonStats) { stat in statCard(stat) }
            }.padding(16)
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .navigationTitle(player.name).navigationBarTitleDisplayMode(.inline)
        .task { await loadStats() }.refreshable { await loadStats() }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            PlayerPortrait(url: player.photo, size: 132)
            Text(player.name).font(.system(size: 28, weight: .bold, design: .rounded)).multilineTextAlignment(.center)
            if let nation = SportsArabic.country(player.nationality), !nation.isEmpty {
                Text(nation).font(.subheadline).foregroundStyle(AppTheme.muted)
            }
            Button(action: toggleFavorite) {
                Label(isFavorite ? "تتم متابعة اللاعب" : "متابعة اللاعب", systemImage: isFavorite ? "star.fill" : "star")
                    .font(.subheadline.bold()).foregroundStyle(isFavorite ? .black : .white)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(isFavorite ? AppTheme.green : AppTheme.soft, in: Capsule())
            }.buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity).padding(22)
        .background(LinearGradient(colors: [AppTheme.cardRaised, AppTheme.greenDeep.opacity(0.34)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(AppTheme.border, lineWidth: 1))
    }

    private var infoCard: some View {
        VStack(spacing: 0) {
            info("الجنسية", SportsArabic.country(player.nationality))
            Divider().overlay(AppTheme.border)
            info("تاريخ الميلاد", player.birth)
            Divider().overlay(AppTheme.border)
            info("الطول", player.height)
            Divider().overlay(AppTheme.border)
            info("الوزن", player.weight)
        }.background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20))
    }

    @MainActor private func loadStats() async {
        loadingStats = true; statsError = nil
        do {
            seasonStats = try await APISportsStore.shared.playerSeasonStats(playerID: player.id)
        } catch {
            statsError = error.localizedDescription
        }
        loadingStats = false
    }

    private func statCard(_ stat: APIPlusPlayerSeasonStat) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 11) {
                RemoteBadge(url: stat.teamLogo).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(SportsArabic.team(stat.team)).bold()
                    Text(SportsArabic.league(stat.league)).font(.caption).foregroundStyle(AppTheme.muted)
                }
                Spacer()
                if let rating = stat.rating, !rating.isEmpty {
                    Text(rating).font(.headline.bold()).foregroundStyle(AppTheme.green)
                        .padding(.horizontal, 10).padding(.vertical, 6).background(AppTheme.green.opacity(0.10), in: Capsule())
                }
            }
            HStack(spacing: 8) {
                metric("مباريات", stat.appearances)
                metric("دقائق", stat.minutes)
                metric("أهداف", stat.goals)
                metric("صناعة", stat.assists)
            }
            if stat.yellowCards > 0 || stat.redCards > 0 {
                HStack {
                    Text("البطاقات").foregroundStyle(AppTheme.muted)
                    Spacer()
                    Text("🟨 \(stat.yellowCards)   🟥 \(stat.redCards)").bold()
                }.font(.subheadline)
            }
        }
        .padding(15)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(AppTheme.border, lineWidth: 1))
    }

    private func metric(_ title: String, _ value: Int) -> some View {
        VStack(spacing: 4) {
            Text("\(value)").font(.headline.bold()).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(AppTheme.muted)
        }.frame(maxWidth: .infinity).padding(.vertical, 10).background(AppTheme.soft, in: RoundedRectangle(cornerRadius: 12))
    }

    private func info(_ title: String, _ value: String?) -> some View {
        HStack { Text(title).foregroundStyle(AppTheme.muted); Spacer(); Text((value?.isEmpty == false ? value : nil) ?? "غير متاح").bold() }
            .padding(.horizontal, 15).padding(.vertical, 14)
    }

    private func toggleFavorite() {
        var ids = Set(SavedFavoriteIDs.parse(favoritePlayerIDs))
        if ids.contains(player.id) { ids.remove(player.id) } else { ids.insert(player.id) }
        favoritePlayerIDs = ids.sorted().joined(separator: ",")
    }
}
