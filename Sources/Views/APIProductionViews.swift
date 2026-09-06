import SwiftUI

struct APIKeySetupView: View {
    @AppStorage(APIFootballClient.keyDefaultsName) private var apiKey = ""
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("ربط بيانات كرة القدم") {
                    SecureField("API-Football Key", text: $draft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("المفتاح يُحفظ على جهازك فقط ولا يتم رفعه إلى GitHub.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button("حفظ وتفعيل البيانات") {
                        apiKey = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("تفعيل البيانات الحقيقية")
            .onAppear { draft = apiKey }
        }
    }
}

struct APIHomeView: View {
    @StateObject private var store = APISportsStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    TopBar(title: nil, showsLogo: true)

                    if store.loading && store.today.isEmpty {
                        ProgressView("جاري تحميل المباريات الحقيقية...")
                            .tint(AppTheme.green)
                            .padding(.top, 50)
                    } else if !APIFootballClient.hasKey {
                        ContentUnavailableView(
                            "أضف مفتاح API-Football",
                            systemImage: "key.fill",
                            description: Text("من المزيد ← إعداد مصدر البيانات")
                        )
                        .foregroundStyle(.white)
                        .padding(.top, 50)
                    } else {
                        homeHeader
                        ForEach(store.today.prefix(8)) { match in
                            NavigationLink {
                                APIMatchDetailView(match: match)
                            } label: {
                                APICompactMatchCard(match: match)
                            }
                            .buttonStyle(.plain)
                        }

                        if store.today.isEmpty {
                            ContentUnavailableView("لا توجد مباريات اليوم", systemImage: "soccerball")
                        }
                    }
                }
                .padding(.bottom, 28)
            }
            .refreshable { await store.refreshToday(force: true) }
            .task { await store.refreshToday() }
            .background(AppTheme.bg.ignoresSafeArea())
        }
    }

    private var homeHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("مباريات اليوم").font(.title2.bold())
                Text("بيانات مباشرة من API-Football")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            Spacer()
            if let date = store.lastUpdated {
                Text(date, style: .time)
                    .font(.caption)
                    .foregroundStyle(AppTheme.green)
            }
        }
        .padding(.horizontal, 16)
    }
}

struct APIMatchesView: View {
    @StateObject private var store = APISportsStore.shared
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var matches: [APIPlusMatch] = []
    @State private var loading = false
    @State private var filter = "الكل"

    private var days: [Date] {
        (-3...3).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: Date()) }
    }

    private var filtered: [APIPlusMatch] {
        switch filter {
        case "مباشر":
            return matches.filter { store.isLive($0.status) }
        case "القادمة":
            return matches.filter { $0.homeScore == nil && !$0.status.uppercased().contains("FT") }
        case "المنتهية":
            return matches.filter { ["FT", "AET", "PEN"].contains($0.status.uppercased()) }
        default:
            return matches
        }
    }

    private var grouped: [(String, [APIPlusMatch])] {
        Dictionary(grouping: filtered, by: \.league)
            .map { ($0.key, $0.value) }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    TopBar(title: "المباريات")
                    dateStrip
                    SegmentBar(items: ["الكل", "مباشر", "القادمة", "المنتهية"], selected: $filter)

                    if loading {
                        ProgressView().tint(AppTheme.green).padding(.top, 40)
                    } else if !APIFootballClient.hasKey {
                        ContentUnavailableView("مصدر البيانات غير مفعّل", systemImage: "key.fill")
                    } else if filtered.isEmpty {
                        ContentUnavailableView("لا توجد مباريات", systemImage: "soccerball")
                    } else {
                        ForEach(grouped, id: \.0) { league, items in
                            HStack {
                                Text(league).font(.headline)
                                Spacer()
                                Text("\(items.count)").foregroundStyle(AppTheme.muted)
                            }
                            .padding(.horizontal, 16)

                            ForEach(items) { match in
                                NavigationLink {
                                    APIMatchDetailView(match: match)
                                } label: {
                                    APICompactMatchCard(match: match)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.bottom, 30)
            }
            .refreshable { await load() }
            .task { await load() }
            .onChange(of: selectedDate) { _, _ in Task { await load() } }
            .background(AppTheme.bg.ignoresSafeArea())
        }
    }

    private var dateStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(days, id: \.self) { day in
                    Button { selectedDate = day } label: {
                        VStack(spacing: 3) {
                            Text(Calendar.current.isDateInToday(day) ? "اليوم" : day.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.caption)
                            Text(day.formatted(.dateTime.day())).bold()
                        }
                        .frame(width: 62)
                        .padding(.vertical, 8)
                        .background(
                            Calendar.current.isDate(day, inSameDayAs: selectedDate) ? AppTheme.green : AppTheme.card,
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .foregroundStyle(Calendar.current.isDate(day, inSameDayAs: selectedDate) ? .black : .white)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @MainActor
    private func load() async {
        guard APIFootballClient.hasKey else {
            matches = []
            return
        }
        loading = true
        defer { loading = false }
        matches = (try? await store.fixtures(date: selectedDate)) ?? []
    }
}

struct APICompactMatchCard: View {
    let match: APIPlusMatch

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(match.league)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
                Spacer()
                Text(match.status.isEmpty ? "موعد" : match.status)
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.green)
            }

            HStack(spacing: 12) {
                team(match.home, match.homeLogo)
                Spacer()
                VStack(spacing: 4) {
                    if let home = match.homeScore, let away = match.awayScore {
                        Text("\(home) - \(away)").font(.title2.bold())
                    } else if let date = match.date {
                        Text(date, style: .time).font(.headline).foregroundStyle(AppTheme.green)
                    }
                    if let elapsed = match.elapsed {
                        Text("\(elapsed)′").font(.caption2).foregroundStyle(AppTheme.green)
                    }
                }
                Spacer()
                team(match.away, match.awayLogo)
            }
        }
        .foregroundStyle(.white)
        .padding(15)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 16)
    }

    private func team(_ name: String, _ logo: String?) -> some View {
        VStack(spacing: 5) {
            RemoteBadge(url: logo).frame(width: 42, height: 42)
            Text(name).font(.caption.bold()).lineLimit(2).frame(maxWidth: 95)
        }
    }
}

@MainActor
final class APIMatchDetailStore: ObservableObject {
    @Published var events: [APIEventItem] = []
    @Published var stats: [APIStatisticTeam] = []
    @Published var lineups: [APILineupItem] = []
    @Published var loading = false

    func load(_ id: String) async {
        loading = true
        defer { loading = false }

        async let eventsResponse: APIEnvelope<[APIEventItem]>? = try? APIFootballClient.get(
            "fixtures/events",
            query: [.init(name: "fixture", value: id)]
        )
        async let statsResponse: APIEnvelope<[APIStatisticTeam]>? = try? APIFootballClient.get(
            "fixtures/statistics",
            query: [.init(name: "fixture", value: id)]
        )
        async let lineupResponse: APIEnvelope<[APILineupItem]>? = try? APIFootballClient.get(
            "fixtures/lineups",
            query: [.init(name: "fixture", value: id)]
        )

        let result = await (eventsResponse, statsResponse, lineupResponse)
        events = result.0?.response ?? []
        stats = result.1?.response ?? []
        lineups = result.2?.response ?? []
    }
}

struct APIMatchDetailView: View {
    let match: APIPlusMatch
    @StateObject private var store = APIMatchDetailStore()
    @State private var tab = "الأحداث"

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                APICompactMatchCard(match: match)
                SegmentBar(items: ["الأحداث", "الإحصائيات", "التشكيلة"], selected: $tab)

                if store.loading {
                    ProgressView().tint(AppTheme.green).padding(40)
                } else if tab == "الأحداث" {
                    eventsView
                } else if tab == "الإحصائيات" {
                    statsView
                } else {
                    lineupsView
                }
            }
            .padding(.vertical, 12)
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .navigationTitle("مركز المباراة")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load(match.id) }
    }

    private var eventsView: some View {
        VStack(spacing: 0) {
            if store.events.isEmpty {
                unavailable("لا توجد أحداث منشورة")
            } else {
                ForEach(Array(store.events.enumerated()), id: \.offset) { _, event in
                    HStack {
                        Text("\(event.time.elapsed ?? 0)′")
                            .foregroundStyle(AppTheme.green)
                            .frame(width: 42)
                        VStack(alignment: .leading) {
                            Text(event.player.name ?? event.team.name ?? "حدث").bold()
                            Text(event.detail ?? event.type ?? "")
                                .font(.caption)
                                .foregroundStyle(AppTheme.muted)
                        }
                        Spacer()
                    }
                    .padding(12)
                    Divider().overlay(Color.white.opacity(0.08))
                }
            }
        }
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 16)
    }

    private var statsView: some View {
        VStack(spacing: 12) {
            if store.stats.isEmpty {
                unavailable("الإحصائيات غير متاحة")
            } else {
                ForEach(Array(store.stats.enumerated()), id: \.offset) { _, team in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(team.team.name ?? "فريق")
                            .font(.headline)
                            .foregroundStyle(AppTheme.green)
                        ForEach(Array(team.statistics.enumerated()), id: \.offset) { _, stat in
                            HStack {
                                Text(stat.type ?? "")
                                Spacer()
                                Text(stat.value?.text ?? "0").bold()
                            }
                            .font(.subheadline)
                        }
                    }
                    .padding(14)
                    .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var lineupsView: some View {
        VStack(spacing: 12) {
            if store.lineups.isEmpty {
                unavailable("التشكيلة غير متاحة")
            } else {
                ForEach(Array(store.lineups.enumerated()), id: \.offset) { _, lineup in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(lineup.team.name ?? "فريق") • \(lineup.formation ?? "")")
                            .font(.headline)
                            .foregroundStyle(AppTheme.green)
                        ForEach(Array((lineup.startXI ?? []).enumerated()), id: \.offset) { _, slot in
                            HStack {
                                Text(slot.player.number.map(String.init) ?? "-").frame(width: 28)
                                Text(slot.player.name ?? "لاعب")
                                Spacer()
                                Text(slot.player.pos ?? "").foregroundStyle(AppTheme.muted)
                            }
                            .font(.subheadline)
                        }
                    }
                    .padding(14)
                    .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func unavailable(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(AppTheme.muted)
            .frame(maxWidth: .infinity)
            .padding(30)
    }
}

struct APIDiscoverView: View {
    @State private var query = ""
    @State private var teams: [APIPlusTeam] = []
    @State private var players: [APIPlusPlayer] = []
    @State private var loading = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if loading {
                    ProgressView().tint(AppTheme.green).padding(.top, 40)
                }

                if !teams.isEmpty {
                    section("الأندية")
                    ForEach(teams) { team in
                        NavigationLink {
                            APITeamView(team: team)
                        } label: {
                            teamRow(team)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !players.isEmpty {
                    section("اللاعبون")
                    ForEach(players) { player in
                        NavigationLink {
                            APIPlayerView(player: player)
                        } label: {
                            playerRow(player)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !loading && teams.isEmpty && players.isEmpty {
                    ContentUnavailableView(
                        "ابحث عن نادي أو لاعب",
                        systemImage: "magnifyingglass",
                        description: Text("مثال: Al Hilal أو Cristiano Ronaldo")
                    )
                    .padding(.top, 70)
                }
            }
            .padding(.bottom, 30)
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .navigationTitle("البحث الحقيقي")
        .searchable(text: $query, prompt: "اسم النادي أو اللاعب")
        .onSubmit(of: .search) { Task { await search() } }
    }

    @MainActor
    private func search() async {
        guard query.count >= 2, APIFootballClient.hasKey else { return }
        loading = true
        defer { loading = false }

        async let teamResults = try? APISportsStore.shared.searchTeams(query)
        async let playerResults = try? APISportsStore.shared.searchPlayers(query)
        let result = await (teamResults, playerResults)
        teams = result.0 ?? []
        players = result.1 ?? []
    }

    private func section(_ text: String) -> some View {
        HStack {
            Text(text).font(.title3.bold())
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private func teamRow(_ team: APIPlusTeam) -> some View {
        HStack {
            RemoteBadge(url: team.logo).frame(width: 48, height: 48)
            VStack(alignment: .leading) {
                Text(team.name).bold()
                Text([team.country, team.city].compactMap { $0 }.joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            Spacer()
            Image(systemName: "chevron.left")
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 16)
    }

    private func playerRow(_ player: APIPlusPlayer) -> some View {
        HStack {
            RemoteBadge(url: player.photo).frame(width: 48, height: 48)
            VStack(alignment: .leading) {
                Text(player.name).bold()
                Text(player.nationality ?? "")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            Spacer()
            Image(systemName: "chevron.left")
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 16)
    }
}

struct APITeamView: View {
    let team: APIPlusTeam
    @State private var next: [APIPlusMatch] = []
    @State private var last: [APIPlusMatch] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                RemoteBadge(url: team.logo).frame(width: 90, height: 90)
                Text(team.name).font(.title.bold())
                Text([team.country, team.city, team.venue].compactMap { $0 }.joined(separator: " • "))
                    .foregroundStyle(AppTheme.muted)
                    .multilineTextAlignment(.center)

                section("القادمة")
                ForEach(next) { APICompactMatchCard(match: $0) }
                section("آخر النتائج")
                ForEach(last) { APICompactMatchCard(match: $0) }
            }
            .padding(.vertical, 16)
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .task {
            async let upcoming = try? APISportsStore.shared.teamFixtures(teamID: team.id, next: true)
            async let recent = try? APISportsStore.shared.teamFixtures(teamID: team.id, next: false)
            let result = await (upcoming, recent)
            next = result.0 ?? []
            last = result.1 ?? []
        }
        .navigationTitle(team.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ text: String) -> some View {
        HStack {
            Text(text).font(.title3.bold())
            Spacer()
        }
        .padding(.horizontal, 16)
    }
}

struct APIPlayerView: View {
    let player: APIPlusPlayer

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                RemoteBadge(url: player.photo).frame(width: 120, height: 120)
                Text(player.name).font(.title.bold())
                VStack(spacing: 10) {
                    row("الجنسية", player.nationality)
                    row("تاريخ الميلاد", player.birth)
                    row("الطول", player.height)
                    row("الوزن", player.weight)
                }
                .padding(18)
                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
            }
            .padding(16)
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .navigationTitle("اللاعب")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, _ value: String?) -> some View {
        HStack {
            Text(title).foregroundStyle(AppTheme.muted)
            Spacer()
            Text(value ?? "—").bold()
        }
    }
}

struct APIMoreView: View {
    @State private var showKey = false

    var body: some View {
        NavigationStack {
            List {
                Section("مصدر البيانات") {
                    HStack {
                        Label("API-Football", systemImage: "server.rack")
                        Spacer()
                        Text(APIFootballClient.hasKey ? "مفعّل" : "غير مفعّل")
                            .foregroundStyle(APIFootballClient.hasKey ? .green : .orange)
                    }
                    Button("إعداد مصدر البيانات") { showKey = true }
                    Text("المباريات والبحث والفرق واللاعبون والترتيب والتشكيلات والأحداث والإحصائيات تعتمد على المصدر الحقيقي عند تفعيل المفتاح.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("البطولات") {
                    ForEach(LeagueOption.featured) { league in
                        NavigationLink(league.arabicName) {
                            APIStandingsView(league: league)
                        }
                    }
                }

                Section("مركز الانتقالات") {
                    NavigationLink("الانتقالات والأخبار") { EnhancedTransfersView() }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.bg)
            .navigationTitle("المزيد")
            .sheet(isPresented: $showKey) { APIKeySetupView() }
        }
    }
}

struct APIStandingsView: View {
    let league: LeagueOption
    @State private var rows: [APIPlusStanding] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if loading {
                    ProgressView().tint(AppTheme.green).padding(50)
                } else {
                    ForEach(rows) { row in
                        HStack(spacing: 10) {
                            Text("\(row.rank)").frame(width: 26)
                            RemoteBadge(url: row.logo).frame(width: 30, height: 30)
                            Text(row.team).lineLimit(1)
                            Spacer()
                            Text("\(row.played)").foregroundStyle(AppTheme.muted).frame(width: 28)
                            Text("\(row.points)").bold().frame(width: 32)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        Divider().overlay(Color.white.opacity(0.08))
                    }
                }
            }
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .navigationTitle(league.arabicName)
        .task {
            rows = (try? await APISportsStore.shared.standings(leagueID: league.id)) ?? []
            loading = false
        }
    }
}
