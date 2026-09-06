import SwiftUI

struct V2MatchesView: View {
    @StateObject private var store = APISportsStore.shared
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var matches: [APIPlusMatch] = []
    @State private var filter = "الكل"
    @State private var loading = false

    private var days: [Date] { (-3...3).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: Date()) } }
    private var filtered: [APIPlusMatch] {
        switch filter {
        case "مباشر": return matches.filter { store.isLive($0.status) }
        case "القادمة": return matches.filter { $0.homeScore == nil && !["FT","AET","PEN"].contains($0.status.uppercased()) }
        case "المنتهية": return matches.filter { ["FT","AET","PEN"].contains($0.status.uppercased()) }
        default: return matches
        }
    }
    private var grouped: [(String,[APIPlusMatch])] { Dictionary(grouping: filtered, by: \.league).map { ($0.key,$0.value) }.sorted { $0.0 < $1.0 } }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    TopBar(title: "المباريات")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(days, id: \.self) { day in
                                Button { selectedDate = day } label: {
                                    VStack(spacing: 3) {
                                        Text(Calendar.current.isDateInToday(day) ? "اليوم" : day.formatted(.dateTime.weekday(.abbreviated))).font(.caption)
                                        Text(day.formatted(.dateTime.day())).bold()
                                    }
                                    .frame(width: 62).padding(.vertical, 8)
                                    .background(Calendar.current.isDate(day, inSameDayAs: selectedDate) ? AppTheme.green : AppTheme.card, in: RoundedRectangle(cornerRadius: 14))
                                    .foregroundStyle(Calendar.current.isDate(day, inSameDayAs: selectedDate) ? .black : .white)
                                }
                            }
                        }.padding(.horizontal, 16)
                    }
                    SegmentBar(items: ["الكل","مباشر","القادمة","المنتهية"], selected: $filter)
                    if loading { ProgressView().tint(AppTheme.green).padding(40) }
                    else if filtered.isEmpty { ContentUnavailableView("لا توجد مباريات", systemImage: "soccerball") }
                    else {
                        ForEach(grouped, id: \.0) { league, items in
                            HStack { Text(league).font(.headline); Spacer(); Text("\(items.count)").foregroundStyle(AppTheme.muted) }.padding(.horizontal, 16)
                            ForEach(items) { match in
                                NavigationLink { V2MatchCenterView(match: match) } label: { APICompactMatchCard(match: match) }.buttonStyle(.plain)
                            }
                        }
                    }
                }.padding(.bottom, 30)
            }
            .background(AppTheme.bg.ignoresSafeArea())
            .task { await load() }
            .refreshable { await load() }
            .onChange(of: selectedDate) { _, _ in Task { await load() } }
        }
    }

    @MainActor private func load() async {
        guard APIFootballClient.hasKey else { matches = []; return }
        loading = true; defer { loading = false }
        matches = (try? await store.fixtures(date: selectedDate)) ?? []
    }
}

@MainActor final class V2MatchCenterStore: ObservableObject {
    @Published var events: [APIEventItem] = []
    @Published var stats: [APIStatisticTeam] = []
    @Published var lineups: [APILineupItem] = []
    @Published var h2h: [APIPlusMatch] = []
    @Published var loading = false

    func load(_ match: APIPlusMatch) async {
        loading = true; defer { loading = false }
        async let e: APIEnvelope<[APIEventItem]>? = try? APIFootballClient.get("fixtures/events", query: [.init(name: "fixture", value: match.id)])
        async let s: APIEnvelope<[APIStatisticTeam]>? = try? APIFootballClient.get("fixtures/statistics", query: [.init(name: "fixture", value: match.id)])
        async let l: APIEnvelope<[APILineupItem]>? = try? APIFootballClient.get("fixtures/lineups", query: [.init(name: "fixture", value: match.id)])
        async let h: APIEnvelope<[APIFixture]>? = {
            guard let home = match.homeID, let away = match.awayID else { return nil }
            return try? await APIFootballClient.get("fixtures/headtohead", query: [.init(name: "h2h", value: "\(home)-\(away)"), .init(name: "last", value: "5")])
        }()
        let r = await (e,s,l,h)
        events = r.0?.response ?? []
        stats = r.1?.response ?? []
        lineups = r.2?.response ?? []
        h2h = (r.3?.response ?? []).map { item in
            APIPlusMatch(id: String(item.fixture.id), leagueID: item.league.id.map(String.init), league: item.league.name ?? "كرة القدم", leagueLogo: item.league.logo, homeID: item.teams.home.id.map(String.init), home: item.teams.home.name ?? "—", homeLogo: item.teams.home.logo, awayID: item.teams.away.id.map(String.init), away: item.teams.away.name ?? "—", awayLogo: item.teams.away.logo, homeScore: item.goals.home, awayScore: item.goals.away, date: item.fixture.date.flatMap { ISO8601DateFormatter().date(from: $0) }, status: item.fixture.status.short ?? item.fixture.status.long ?? "", elapsed: item.fixture.status.elapsed)
        }
    }
}

struct V2MatchCenterView: View {
    let match: APIPlusMatch
    @StateObject private var store = V2MatchCenterStore()
    @State private var tab = "نظرة عامة"

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                SegmentBar(items: ["نظرة عامة","الأحداث","الإحصائيات","التشكيلة","المواجهات"], selected: $tab)
                if store.loading { ProgressView().tint(AppTheme.green).padding(40) }
                else { content }
            }.padding(.vertical, 12)
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .navigationTitle("مركز المباراة")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load(match) }
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack { Text(match.league).font(.caption).foregroundStyle(AppTheme.muted); Spacer(); Text(statusText).font(.caption.bold()).foregroundStyle(AppTheme.green) }
            HStack {
                team(match.home, match.homeLogo)
                Spacer()
                VStack(spacing: 5) {
                    if let h = match.homeScore, let a = match.awayScore { Text("\(h) - \(a)").font(.system(size: 34, weight: .black, design: .rounded)) }
                    else if let date = match.date { Text(date, style: .time).font(.title2.bold()) }
                    if let elapsed = match.elapsed { Text("\(elapsed)′").font(.caption).foregroundStyle(AppTheme.green) }
                }
                Spacer()
                team(match.away, match.awayLogo)
            }
        }
        .foregroundStyle(.white).padding(18)
        .background(LinearGradient(colors: [AppTheme.card, AppTheme.green.opacity(0.10)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 16)
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case "الأحداث": eventsView
        case "الإحصائيات": statsView
        case "التشكيلة": lineupsView
        case "المواجهات": h2hView
        default: overview
        }
    }

    private var overview: some View {
        VStack(spacing: 12) {
            infoRow("الحالة", statusText)
            infoRow("البطولة", match.league)
            if let date = match.date { infoRow("الموعد", date.formatted(date: .abbreviated, time: .shortened)) }
            infoRow("الأحداث المتاحة", "\(store.events.count)")
            infoRow("التشكيلات", "\(store.lineups.count)")
        }.padding(16).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
    }

    private var eventsView: some View {
        VStack(spacing: 0) {
            if store.events.isEmpty { unavailable("لا توجد أحداث منشورة") }
            else { ForEach(Array(store.events.enumerated()), id: \.offset) { _, e in HStack { Text("\(e.time.elapsed ?? 0)′").foregroundStyle(AppTheme.green).frame(width: 42); VStack(alignment: .leading) { Text(e.player.name ?? e.team.name ?? "حدث").bold(); Text(e.detail ?? e.type ?? "").font(.caption).foregroundStyle(AppTheme.muted) }; Spacer() }.padding(12); Divider().overlay(Color.white.opacity(0.08)) } }
        }.background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
    }

    private var statsView: some View {
        VStack(spacing: 12) {
            if store.stats.isEmpty { unavailable("الإحصائيات غير متاحة") }
            else { ForEach(Array(store.stats.enumerated()), id: \.offset) { _, team in VStack(alignment: .leading, spacing: 8) { Text(team.team.name ?? "فريق").font(.headline).foregroundStyle(AppTheme.green); ForEach(Array(team.statistics.enumerated()), id: \.offset) { _, stat in HStack { Text(stat.type ?? ""); Spacer(); Text(stat.value?.text ?? "0").bold() }.font(.subheadline) } }.padding(14).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)) } }
        }.padding(.horizontal, 16)
    }

    private var lineupsView: some View {
        VStack(spacing: 12) {
            if store.lineups.isEmpty { unavailable("التشكيلة غير متاحة") }
            else { ForEach(Array(store.lineups.enumerated()), id: \.offset) { _, lineup in VStack(alignment: .leading, spacing: 8) { Text("\(lineup.team.name ?? "فريق") • \(lineup.formation ?? "")").font(.headline).foregroundStyle(AppTheme.green); ForEach(Array((lineup.startXI ?? []).enumerated()), id: \.offset) { _, slot in HStack { Text(slot.player.number.map(String.init) ?? "-").frame(width: 28); Text(slot.player.name ?? "لاعب"); Spacer(); Text(slot.player.pos ?? "").foregroundStyle(AppTheme.muted) }.font(.subheadline) } }.padding(14).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)) } }
        }.padding(.horizontal, 16)
    }

    private var h2hView: some View {
        VStack(spacing: 10) {
            if store.h2h.isEmpty { unavailable("لا توجد مواجهات سابقة متاحة") }
            else { ForEach(store.h2h) { APICompactMatchCard(match: $0) } }
        }
    }

    private func team(_ name: String, _ logo: String?) -> some View { VStack(spacing: 7) { RemoteBadge(url: logo).frame(width: 68, height: 68); Text(name).font(.subheadline.bold()).multilineTextAlignment(.center).lineLimit(2).frame(width: 105) } }
    private func infoRow(_ title: String, _ value: String) -> some View { HStack { Text(title).foregroundStyle(AppTheme.muted); Spacer(); Text(value).bold() } }
    private func unavailable(_ text: String) -> some View { Text(text).foregroundStyle(AppTheme.muted).frame(maxWidth: .infinity).padding(30) }
    private var statusText: String { let s = match.status.uppercased(); if APISportsStore.shared.isLive(s) { return match.elapsed.map { "مباشر • \($0)′" } ?? "مباشر" }; switch s { case "FT": return "انتهت"; case "HT": return "بين الشوطين"; case "NS": return "لم تبدأ"; case "PST": return "مؤجلة"; case "CANC": return "ملغاة"; case "AET": return "وقت إضافي"; case "PEN": return "ركلات ترجيح"; default: return match.status.isEmpty ? "موعد" : match.status } }
}
