import SwiftUI
import UserNotifications

struct V2MatchesView: View {
    @StateObject private var store = APISportsStore.shared
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var dayAnchor = Calendar.current.startOfDay(for: Date())
    @State private var resource = PageResource<[APIPlusMatch]>()
    @State private var filter = "الكل"
    @State private var retryID = 0

    private var selectedDay: Date { Calendar.current.startOfDay(for: selectedDate) }
    private var dayKey: String { String(selectedDay.timeIntervalSince1970) }
    private var hasValue: Bool { resource.key == dayKey && resource.value != nil }
    private var matches: [APIPlusMatch] { hasValue ? (resource.value ?? []) : [] }
    private var days: [Date] { (-3...3).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: dayAnchor) } }

    private var filtered: [APIPlusMatch] {
        switch filter {
        case "مباشر": return matches.filter { store.isLive($0.status) }
        case "القادمة": return matches.filter { FixturePhase.isUpcoming($0.status) }
        case "المنتهية": return matches.filter { FixturePhase.isFinished($0.status) }
        default: return matches
        }
    }

    private struct LeagueGroup: Identifiable {
        let id: String
        let name: String
        let items: [APIPlusMatch]
    }
    private var grouped: [LeagueGroup] {
        Dictionary(grouping: filtered, by: { $0.leagueID ?? $0.league })
            .map { LeagueGroup(id: $0.key, name: $0.value.first?.league ?? "", items: $0.value) }
            .sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
    }

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
                    SegmentBar(items: ["الكل", "مباشر", "القادمة", "المنتهية"], selected: $filter)
                    PageLoadFeedback(
                        loading: resource.isLoading || resource.key != dayKey,
                        hasValue: hasValue,
                        message: resource.key == dayKey ? resource.errorMessage : nil,
                        updatedAt: hasValue ? resource.lastUpdated : nil
                    ) { retryID += 1 }

                    if hasValue && !resource.isLoading && resource.errorMessage == nil && filtered.isEmpty {
                        ContentUnavailableView(
                            matches.isEmpty ? "لا توجد مباريات منشورة لهذا اليوم" : "لا توجد مباريات تطابق هذا الفلتر",
                            systemImage: "soccerball",
                            description: Text("غيّر اليوم أو الفلتر، أو اسحب الصفحة للتحديث.")
                        )
                    }
                    ForEach(grouped) { group in
                        HStack {
                            Text(group.name).font(.headline)
                            Spacer()
                            Text("\(group.items.count)").foregroundStyle(AppTheme.muted)
                        }.padding(.horizontal, 16)
                        ForEach(group.items) { match in
                            NavigationLink { V2MatchCenterView(match: match) } label: {
                                APICompactMatchCard(match: match)
                            }.buttonStyle(.plain)
                        }
                    }
                }.padding(.bottom, 30)
            }
            .background(AppTheme.bg.ignoresSafeArea())
            .task(id: "\(dayKey)|\(retryID)") { await load(force: retryID > 0) }
            .refreshable { await load(force: true) }
            .onDisappear { resource.invalidate() }
            // Reuse the app's existing foreground refresh instead of a second timer.
            .onReceive(store.$lastUpdated) { updatedAt in
                guard let updatedAt, Calendar.current.isDateInToday(selectedDate),
                      resource.key == dayKey, !resource.isLoading else { return }
                let token = resource.begin(key: dayKey)
                resource.succeed(store.today, token: token, at: updatedAt)
            }
        }
    }

    @MainActor private func load(force: Bool = false) async {
        let date = selectedDay
        let key = dayKey
        guard !Task.isCancelled else { return }
        if !force && resource.isFresh(key: key, maxAge: 40) { return }
        let token = resource.begin(key: key)
        defer { resource.cancel(token: token) }
        do {
            guard APIFootballClient.isConfigured else { throw APIFootballError.missingConfiguration }
            let result = try await store.fixtures(date: date)
            try Task.checkCancellation()
            guard dayKey == key else { return }
            resource.succeed(result, token: token)
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), dayKey == key else { return }
            resource.fail(error.localizedDescription, token: token)
        }
    }
}

@MainActor
final class V2MatchCenterStore: ObservableObject {
    @Published private(set) var current: APIPlusMatch?
    @Published private(set) var events: [APIEventItem] = []
    @Published private(set) var stats: [APIStatisticTeam] = []
    @Published private(set) var lineups: [APILineupItem] = []
    @Published private(set) var h2h: [APIPlusMatch] = []
    @Published private(set) var progress = MatchCenterProgress()
    private var lastObserved: APIPlusMatch?

    var lastLiveUpdate: Date? { progress.state(.fixture).lastUpdated }

    private func prepare(_ match: APIPlusMatch) {
        guard progress.select(matchID: match.id) else { return }
        current = match
        events = []; stats = []; lineups = []; h2h = []
        lastObserved = nil
    }

    func cancelPending() { progress.invalidate() }

    func load(_ match: APIPlusMatch, force: Bool = false) async {
        guard !Task.isCancelled else { return }
        prepare(match)
        let lackedTeamIDs = current?.homeID == nil || current?.awayID == nil
        await fetchSections(MatchDataSection.allCases, match: match, force: force)
        // The fixture response may supply team IDs absent from the entry card.
        if lackedTeamIDs, !Task.isCancelled, progress.matchID == match.id,
           progress.state(.h2h).value == nil, current?.homeID != nil, current?.awayID != nil {
            await loadSection(.h2h, match: match)
        }
    }

    func refreshLive(_ match: APIPlusMatch, sections: [MatchDataSection]) async {
        guard !Task.isCancelled else { return }
        await fetchSections(Array(Set([.fixture] + sections)), match: match, force: false)
    }

    private func fetchSections(_ sections: [MatchDataSection], match: APIPlusMatch, force: Bool) async {
        await withTaskGroup(of: Void.self) { group in
            for section in sections {
                group.addTask { await self.loadSection(section, match: match, force: force) }
            }
        }
    }

    func loadSection(_ section: MatchDataSection, match: APIPlusMatch, force: Bool = false) async {
        guard !Task.isCancelled else { return }
        prepare(match)
        let displayed = current ?? match
        if section == .h2h {
            guard displayed.homeID != nil, displayed.awayID != nil else {
                progress.markUnavailable(.h2h)
                return
            }
            progress.markAvailable(.h2h)
        }
        guard let token = progress.begin(section, force: force) else { return }
        defer { progress.cancel(section, token: token) }
        do {
            switch section {
            case .fixture:
                let result: APIEnvelope<[APIFixture]> = try await APIFootballClient.get("fixtures", query: [.init(name: "id", value: match.id)])
                try Task.checkCancellation()
                guard progress.matchID == match.id else { return }
                guard let item = result.response.first(where: { String($0.fixture.id) == match.id }) else {
                    throw APIFootballError.badResponse
                }
                let updated = map(item)
                let previous = lastObserved
                let previousTime = lastLiveUpdate
                guard progress.succeed(.fixture, token: token, hasContent: true) else { return }
                current = updated
                lastObserved = updated
                // Initial loads and long gaps do not generate catch-up goal alerts.
                if let previousTime, Date().timeIntervalSince(previousTime) < 120 {
                    notifyIfNeeded(previous: previous, updated: updated)
                }
            case .events:
                let result: APIEnvelope<[APIEventItem]> = try await APIFootballClient.get("fixtures/events", query: [.init(name: "fixture", value: match.id)])
                try Task.checkCancellation()
                guard progress.matchID == match.id, progress.succeed(.events, token: token, hasContent: !result.response.isEmpty) else { return }
                events = result.response
            case .stats:
                let result: APIEnvelope<[APIStatisticTeam]> = try await APIFootballClient.get("fixtures/statistics", query: [.init(name: "fixture", value: match.id)])
                try Task.checkCancellation()
                guard progress.matchID == match.id, progress.succeed(.stats, token: token, hasContent: !result.response.isEmpty) else { return }
                stats = result.response
            case .lineups:
                let result: APIEnvelope<[APILineupItem]> = try await APIFootballClient.get("fixtures/lineups", query: [.init(name: "fixture", value: match.id)])
                try Task.checkCancellation()
                guard progress.matchID == match.id, progress.succeed(.lineups, token: token, hasContent: !result.response.isEmpty) else { return }
                lineups = result.response
            case .h2h:
                guard let home = displayed.homeID, let away = displayed.awayID else { return }
                let result: APIEnvelope<[APIFixture]> = try await APIFootballClient.get("fixtures/headtohead", query: [.init(name: "h2h", value: "\(home)-\(away)"), .init(name: "last", value: "5")])
                try Task.checkCancellation()
                guard progress.matchID == match.id, progress.succeed(.h2h, token: token, hasContent: !result.response.isEmpty) else { return }
                h2h = result.response.map(map)
            }
        } catch {
            guard !Task.isCancelled, !(error is CancellationError),
                  (error as? URLError)?.code != .cancelled, progress.matchID == match.id else { return }
            progress.fail(section, token: token, message: error.localizedDescription)
        }
    }

    private func map(_ item: APIFixture) -> APIPlusMatch {
        APIPlusMatch(
            id: String(item.fixture.id), leagueID: item.league.id.map(String.init), league: item.league.name ?? "كرة القدم", leagueLogo: item.league.logo,
            homeID: item.teams.home.id.map(String.init), home: item.teams.home.name ?? "—", homeLogo: item.teams.home.logo,
            awayID: item.teams.away.id.map(String.init), away: item.teams.away.name ?? "—", awayLogo: item.teams.away.logo,
            homeScore: item.goals.home, awayScore: item.goals.away,
            date: item.fixture.date.flatMap { ISO8601DateFormatter().date(from: $0) },
            status: item.fixture.status.short ?? item.fixture.status.long ?? "", elapsed: item.fixture.status.elapsed
        )
    }

    private func notifyIfNeeded(previous: APIPlusMatch?, updated: APIPlusMatch) {
        guard let previous, previous.id == updated.id,
              UserDefaults.standard.bool(forKey: "notificationsEnabled"),
              SavedFavoriteIDs.parse(UserDefaults.standard.string(forKey: "followedMatchIDs") ?? "").contains(updated.id),
              let notice = MatchLivePolicy.notice(previousStatus: previous.status, status: updated.status, previousHome: previous.homeScore, previousAway: previous.awayScore, home: updated.homeScore, away: updated.awayScore) else { return }
        let title: String
        switch notice {
        case .started: title = "بدأت المباراة"
        case .scoreChanged: title = "تغيرت النتيجة"
        case .finished: title = "انتهت المباراة"
        }
        var body = "\(updated.home) ضد \(updated.away)"
        if let home = updated.homeScore, let away = updated.awayScore {
            body = "\(updated.home) \(home) - \(away) \(updated.away)"
        }
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        content.userInfo = ["matchID": updated.id]
        let request = UNNotificationRequest(identifier: "ninetyplus.v2.\(updated.id).\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

struct V2MatchCenterView: View {
    let match: APIPlusMatch
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = V2MatchCenterStore()
    @State private var tab = "نظرة عامة"
    @State private var visible = false
    @State private var retryID = 0
    @State private var retrySection: MatchDataSection?
    @State private var followBusy = false
    @State private var permissionNotice: String?
    @AppStorage("followedMatchIDs") private var followedMatchIDs = ""
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false

    private var displayMatch: APIPlusMatch { store.current ?? match }
    private var isFollowed: Bool { SavedFavoriteIDs.parse(followedMatchIDs).contains(match.id) }
    private var isActive: Bool { visible && scenePhase == .active }
    private var lifecycleKey: String { "\(match.id):\(isActive)" }
    private var tabSections: [MatchDataSection] {
        switch tab {
        case "الأحداث": return [.events]
        case "الإحصائيات": return [.stats]
        case "التشكيلة": return [.lineups]
        case "المواجهات": return [.h2h]
        case "تحليل 90+": return [.events, .stats]
        default: return []
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                followBar
                feedback(.fixture)
                SegmentBar(items: ["نظرة عامة", "تحليل 90+", "الأحداث", "الإحصائيات", "التشكيلة", "المواجهات"], selected: $tab)
                content
            }.padding(.vertical, 12)
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .navigationTitle("مركز المباراة").navigationBarTitleDisplayMode(.inline)
        .onAppear { visible = true }
        .onDisappear { visible = false; store.cancelPending() }
        .task(id: lifecycleKey) {
            guard isActive else { store.cancelPending(); return }
            await store.load(match)
            while !Task.isCancelled && isActive {
                let current = displayMatch
                guard let seconds = MatchLivePolicy.interval(status: current.status, kickoff: current.date) else { break }
                do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                guard !Task.isCancelled && isActive else { return }
                await store.refreshLive(match, sections: tabSections)
            }
        }
        .task(id: "\(lifecycleKey):\(tab)") {
            guard isActive else { return }
            for section in tabSections { await store.loadSection(section, match: match) }
        }
        .task(id: "\(lifecycleKey):retry:\(retryID)") {
            guard isActive, retryID > 0, let retrySection else { return }
            await store.loadSection(retrySection, match: match, force: true)
        }
        .refreshable {
            guard isActive else { return }
            await store.load(match, force: true)
        }
    }

    private var header: some View {
        let m = displayMatch
        return VStack(spacing: 14) {
            HStack {
                Text(m.league).font(.caption).foregroundStyle(AppTheme.muted)
                Spacer()
                Text(MatchLivePolicy.statusText(m.status, elapsed: m.elapsed)).font(.caption.bold()).foregroundStyle(AppTheme.green)
            }
            HStack {
                team(m.home, m.homeLogo); Spacer()
                VStack(spacing: 5) {
                    if !FixturePhase.isUpcoming(m.status), let h = m.homeScore, let a = m.awayScore {
                        Text("\(h) - \(a)").font(.system(size: 34, weight: .black, design: .rounded)).monospacedDigit()
                    } else if let date = m.date { Text(date, style: .time).font(.title2.bold()) }
                    else { Text("—").font(.title2.bold()) }
                }
                Spacer(); team(m.away, m.awayLogo)
            }
        }
        .foregroundStyle(.white).padding(18)
        .background(LinearGradient(colors: [AppTheme.card, AppTheme.green.opacity(0.10)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 16)
    }

    private var followBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button { Task { await toggleFollow() } } label: {
                    Label(isFollowed ? "تتم متابعة المباراة" : "متابعة المباراة", systemImage: isFollowed ? "bell.fill" : "bell")
                        .font(.subheadline.bold()).foregroundStyle(isFollowed ? .black : .white)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(isFollowed ? AppTheme.green : AppTheme.card, in: Capsule())
                }.buttonStyle(.plain).disabled(followBusy)
                Spacer()
                if let date = store.lastLiveUpdate {
                    Text("آخر استلام للنتيجة \(date, style: .relative)").font(.caption2).foregroundStyle(AppTheme.muted)
                }
            }
            if let permissionNotice { Text(permissionNotice).font(.caption).foregroundStyle(AppTheme.muted) }
        }.padding(.horizontal, 16)
    }

    private func feedback(_ section: MatchDataSection) -> some View {
        let state = store.progress.state(section)
        return PageLoadFeedback(
            loading: state.isLoading,
            hasValue: state.value != nil,
            message: state.errorMessage.map { "\(section.title): \($0)" },
            updatedAt: state.lastUpdated
        ) { retrySection = section; retryID += 1 }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case "تحليل 90+":
            feedback(.events); feedback(.stats); insightView
        case "الأحداث":
            feedback(.events); eventsView
        case "الإحصائيات":
            feedback(.stats); statsView
        case "التشكيلة":
            feedback(.lineups); lineupsView
        case "المواجهات":
            feedback(.h2h); h2hView
        default: overview
        }
    }

    private var overview: some View {
        let m = displayMatch
        return VStack(spacing: 12) {
            infoRow("الحالة", MatchLivePolicy.statusText(m.status, elapsed: m.elapsed))
            infoRow("البطولة", m.league)
            if let date = m.date { infoRow("الموعد", date.formatted(date: .abbreviated, time: .shortened)) }
            infoRow("الأحداث المتاحة", countText(.events, store.events.count))
            infoRow("التشكيلات", countText(.lineups, store.lineups.count))
            infoRow("مواجهات سابقة", countText(.h2h, store.h2h.count))
            ForEach(store.progress.errors, id: \.0) { section, _ in
                Button {
                    retrySection = section; retryID += 1
                } label: {
                    Label("إعادة تحميل \(section.title)", systemImage: "arrow.clockwise")
                        .font(.caption.bold()).foregroundStyle(.orange)
                }.disabled(store.progress.state(section).isLoading)
            }
        }.padding(16).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
    }

    private func countText(_ section: MatchDataSection, _ count: Int) -> String {
        let state = store.progress.state(section)
        if state.value != nil { return state.errorMessage == nil ? "\(count)" : "\(count) • آخر بيانات محفوظة" }
        return state.isLoading ? "جارٍ التحميل" : "غير متاح"
    }

    private var insightView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("ملخص البيانات المتاحة", systemImage: "sparkles").font(.headline).foregroundStyle(AppTheme.green)
            if !store.progress.errors.isEmpty {
                Label("بعض الأقسام لم تتحدث. الملخص يستخدم آخر بيانات وصلت، وقد لا يعكس آخر تطورات المباراة.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.orange)
            }
            Text(MatchLivePolicy.summary(status: displayMatch.status, homeName: displayMatch.home, awayName: displayMatch.away, home: displayMatch.homeScore, away: displayMatch.awayScore))
                .font(.body).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(keyFacts, id: \.self) { fact in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.green)
                    Text(fact).font(.subheadline)
                    Spacer(minLength: 0)
                }
            }
            Text("هذا ملخص آلي للبيانات المنشورة، وليس توقعًا للنتيجة. لا تُستبدل المعلومات الناقصة بأرقام تقديرية.")
                .font(.caption).foregroundStyle(AppTheme.muted)
        }.padding(16).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
    }

    private var eventsView: some View {
        VStack(spacing: 0) {
            if store.events.isEmpty && store.progress.mayShowEmpty(.events) { unavailable("لا توجد أحداث منشورة") }
            ForEach(Array(store.events.enumerated()), id: \.offset) { _, event in
                HStack {
                    Text(MatchLivePolicy.eventMinute(elapsed: event.time.elapsed, extra: event.time.extra))
                        .foregroundStyle(AppTheme.green).frame(width: 60)
                    VStack(alignment: .leading) {
                        Text(event.player.name ?? event.team.name ?? "حدث").bold()
                        Text(event.detail ?? event.type ?? "").font(.caption).foregroundStyle(AppTheme.muted)
                    }
                    Spacer()
                }.padding(12)
                Divider().overlay(Color.white.opacity(0.08))
            }
        }.background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
    }

    private var statsView: some View {
        VStack(spacing: 12) {
            if store.stats.isEmpty && store.progress.mayShowEmpty(.stats) { unavailable("الإحصائيات غير متاحة من المصدر") }
            ForEach(Array(store.stats.enumerated()), id: \.offset) { _, teamStats in
                VStack(alignment: .leading, spacing: 8) {
                    Text(teamStats.team.name ?? "فريق").font(.headline).foregroundStyle(AppTheme.green)
                    ForEach(Array(teamStats.statistics.enumerated()), id: \.offset) { _, stat in
                        HStack { Text(stat.type ?? "—"); Spacer(); Text(statText(stat.value)).bold() }.font(.subheadline)
                    }
                }.padding(14).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
            }
        }.padding(.horizontal, 16)
    }

    private func statText(_ value: APIStatValue?) -> String {
        guard let value else { return "—" }
        if case .null = value { return "—" }
        return value.text.isEmpty ? "—" : value.text
    }

    private var lineupsView: some View {
        VStack(spacing: 12) {
            if store.lineups.isEmpty && store.progress.mayShowEmpty(.lineups) { unavailable("التشكيلة غير منشورة حاليًا") }
            ForEach(Array(store.lineups.enumerated()), id: \.offset) { _, lineup in
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(lineup.team.name ?? "فريق") • \(lineup.formation ?? "—")").font(.headline).foregroundStyle(AppTheme.green)
                    ForEach(Array((lineup.startXI ?? []).enumerated()), id: \.offset) { _, slot in
                        HStack {
                            Text(slot.player.number.map(String.init) ?? "—").frame(width: 28)
                            Text(slot.player.name ?? "لاعب"); Spacer()
                            Text(slot.player.pos ?? "").foregroundStyle(AppTheme.muted)
                        }.font(.subheadline)
                    }
                }.padding(14).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
            }
        }.padding(.horizontal, 16)
    }

    private var h2hView: some View {
        VStack(spacing: 10) {
            if store.h2h.isEmpty && store.progress.mayShowEmpty(.h2h) { unavailable("لا توجد مواجهات سابقة متاحة من المصدر") }
            ForEach(store.h2h) { APICompactMatchCard(match: $0) }
        }
    }

    private var keyFacts: [String] {
        var facts: [String] = []
        let goals = store.events.filter { ($0.type ?? "").lowercased().contains("goal") }
        let cards = store.events.filter { ($0.type ?? "").lowercased().contains("card") }
        if !goals.isEmpty { facts.append("عدد أحداث الأهداف المنشورة: \(goals.count).") }
        if !cards.isEmpty { facts.append("عدد أحداث البطاقات المنشورة: \(cards.count).") }
        if store.lineups.count == 2 { facts.append("تشكيلة الفريقين متوفرة من المصدر.") }
        if !store.stats.isEmpty { facts.append("إحصائيات المباراة متوفرة لـ \(store.stats.count) فريق/طرف.") }
        if !store.h2h.isEmpty { facts.append("متوفر \(store.h2h.count) من المواجهات السابقة بين الفريقين.") }
        return facts
    }

    @MainActor private func toggleFollow() async {
        guard !followBusy else { return }
        followBusy = true
        defer { followBusy = false }
        permissionNotice = nil
        if isFollowed {
            var ids = Set(SavedFavoriteIDs.parse(followedMatchIDs))
            ids.remove(match.id)
            followedMatchIDs = ids.sorted().joined(separator: ",")
            return
        }
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            if granted { notificationsEnabled = true }
            else { permissionNotice = "المتابعة محفوظة، لكن إذن التنبيهات غير مفعّل في إعدادات الجهاز." }
        } catch { permissionNotice = "المتابعة محفوظة. تعذر طلب إذن التنبيهات حاليًا." }
        var ids = Set(SavedFavoriteIDs.parse(followedMatchIDs))
        ids.insert(match.id)
        followedMatchIDs = ids.sorted().joined(separator: ",")
    }

    private func team(_ name: String, _ logo: String?) -> some View { VStack(spacing: 7) { RemoteBadge(url: logo).frame(width: 68, height: 68); Text(name).font(.subheadline.bold()).multilineTextAlignment(.center).lineLimit(2).frame(width: 105) } }
    private func infoRow(_ title: String, _ value: String) -> some View { HStack { Text(title).foregroundStyle(AppTheme.muted); Spacer(); Text(value).bold() } }
    private func unavailable(_ text: String) -> some View { Text(text).foregroundStyle(AppTheme.muted).frame(maxWidth: .infinity).padding(30) }
}
