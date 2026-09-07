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
    @Published var current: APIPlusMatch?
    @Published var events: [APIEventItem] = []
    @Published var stats: [APIStatisticTeam] = []
    @Published var lineups: [APILineupItem] = []
    @Published var h2h: [APIPlusMatch] = []
    @Published var loading = false
    @Published var lastLiveUpdate: Date?
    @Published var liveError: String?
    @Published var sectionErrors: [String: String] = [:]

    private var lastObserved: APIPlusMatch?

    private struct FetchResult<T> {
        let value: T?
        let error: String?
    }

    private func capture<T>(_ work: () async throws -> T) async -> FetchResult<T> {
        do { return FetchResult(value: try await work(), error: nil) }
        catch { return FetchResult(value: nil, error: error.localizedDescription) }
    }

    func load(_ match: APIPlusMatch) async {
        loading = true
        liveError = nil
        sectionErrors = [:]
        current = match
        lastObserved = match
        defer { loading = false }

        async let fixture: FetchResult<APIEnvelope<[APIFixture]>> = capture {
            try await APIFootballClient.get("fixtures", query: [.init(name: "id", value: match.id)])
        }
        async let e: FetchResult<APIEnvelope<[APIEventItem]>> = capture {
            try await APIFootballClient.get("fixtures/events", query: [.init(name: "fixture", value: match.id)])
        }
        async let s: FetchResult<APIEnvelope<[APIStatisticTeam]>> = capture {
            try await APIFootballClient.get("fixtures/statistics", query: [.init(name: "fixture", value: match.id)])
        }
        async let l: FetchResult<APIEnvelope<[APILineupItem]>> = capture {
            try await APIFootballClient.get("fixtures/lineups", query: [.init(name: "fixture", value: match.id)])
        }
        async let h: FetchResult<APIEnvelope<[APIFixture]>>? = {
            guard let home = match.homeID, let away = match.awayID else { return nil }
            return await capture {
                try await APIFootballClient.get("fixtures/headtohead", query: [.init(name: "h2h", value: "\(home)-\(away)"), .init(name: "last", value: "5")])
            }
        }()

        let result = await (fixture, e, s, l, h)
        if let item = result.0.value?.response.first { current = map(item) }
        if let message = result.0.error { sectionErrors["fixture"] = message }

        if let value = result.1.value { events = value.response }
        if let message = result.1.error { sectionErrors["events"] = message }

        if let value = result.2.value { stats = value.response }
        if let message = result.2.error { sectionErrors["stats"] = message }

        if let value = result.3.value { lineups = value.response }
        if let message = result.3.error { sectionErrors["lineups"] = message }

        if let hResult = result.4 {
            if let value = hResult.value { h2h = value.response.map(map) }
            if let message = hResult.error { sectionErrors["h2h"] = message }
        }

        let failed = sectionErrors.count
        if failed > 0 {
            liveError = failed == 1 ? "تعذر تحميل جزء واحد من بيانات المباراة." : "تعذر تحميل \(failed) أجزاء من بيانات المباراة. البيانات الأخرى ما زالت معروضة."
        }
        lastObserved = current
        lastLiveUpdate = Date()
    }

    func refreshLive(_ fallback: APIPlusMatch) async {
        do {
            async let fixture: APIEnvelope<[APIFixture]> = APIFootballClient.get("fixtures", query: [.init(name: "id", value: fallback.id)])
            async let e: APIEnvelope<[APIEventItem]> = APIFootballClient.get("fixtures/events", query: [.init(name: "fixture", value: fallback.id)])
            async let s: APIEnvelope<[APIStatisticTeam]> = APIFootballClient.get("fixtures/statistics", query: [.init(name: "fixture", value: fallback.id)])
            let result = try await (fixture, e, s)
            if let item = result.0.response.first {
                let updated = map(item)
                notifyIfNeeded(previous: lastObserved, updated: updated)
                current = updated
                lastObserved = updated
            }
            events = result.1.response
            stats = result.2.response
            sectionErrors["fixture"] = nil
            sectionErrors["events"] = nil
            sectionErrors["stats"] = nil
            lastLiveUpdate = Date()
            liveError = nil
        } catch {
            liveError = "تعذر التحديث اللحظي مؤقتًا. آخر بيانات صحيحة ما زالت معروضة."
        }
    }

    func shouldAutoRefresh(_ match: APIPlusMatch) -> Bool {
        let status = match.status.uppercased()
        return APISportsStore.shared.isLive(status) || ["NS", "TBD"].contains(status)
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
        guard let previous,
              UserDefaults.standard.bool(forKey: "notificationsEnabled"),
              followedIDs.contains(updated.id) else { return }

        if previous.homeScore != updated.homeScore || previous.awayScore != updated.awayScore {
            guard updated.homeScore != nil, updated.awayScore != nil else { return }
            sendNotification(title: "تغيرت النتيجة", body: "\(updated.home) \(updated.homeScore ?? 0) - \(updated.awayScore ?? 0) \(updated.away)", id: updated.id)
            return
        }
        if previous.status.uppercased() != updated.status.uppercased() {
            if APISportsStore.shared.isLive(updated.status) {
                sendNotification(title: "بدأت المباراة", body: "\(updated.home) ضد \(updated.away)", id: updated.id)
            } else if ["FT", "AET", "PEN"].contains(updated.status.uppercased()) {
                sendNotification(title: "انتهت المباراة", body: "\(updated.home) \(updated.homeScore ?? 0) - \(updated.awayScore ?? 0) \(updated.away)", id: updated.id)
            }
        }
    }

    private var followedIDs: Set<String> {
        Set((UserDefaults.standard.string(forKey: "followedMatchIDs") ?? "").split(separator: ",").map(String.init))
    }

    private func sendNotification(title: String, body: String, id: String) {
        let content = UNMutableNotificationContent(); content.title = title; content.body = body; content.sound = .default; content.userInfo = ["matchID": id]
        let request = UNNotificationRequest(identifier: "ninetyplus.v2.\(id).\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

struct V2MatchCenterView: View {
    let match: APIPlusMatch
    @StateObject private var store = V2MatchCenterStore()
    @State private var tab = "نظرة عامة"
    @AppStorage("followedMatchIDs") private var followedMatchIDs = ""
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false

    private var displayMatch: APIPlusMatch { store.current ?? match }
    private var isFollowed: Bool { Set(followedMatchIDs.split(separator: ",").map(String.init)).contains(match.id) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                followBar
                SegmentBar(items: ["نظرة عامة", "تحليل 90+", "الأحداث", "الإحصائيات", "التشكيلة", "المواجهات"], selected: $tab)
                if store.loading { ProgressView().tint(AppTheme.green).padding(40) } else { content }
            }.padding(.vertical, 12)
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .navigationTitle("مركز المباراة").navigationBarTitleDisplayMode(.inline)
        .task(id: match.id) {
            await store.load(match)
            while !Task.isCancelled {
                let active = store.current ?? match
                guard store.shouldAutoRefresh(active) else { break }
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                await store.refreshLive(match)
            }
        }
        .refreshable { await store.load(match) }
    }

    private var header: some View {
        let m = displayMatch
        return VStack(spacing: 14) {
            HStack {
                Text(m.league).font(.caption).foregroundStyle(AppTheme.muted)
                Spacer()
                Text(statusText(m)).font(.caption.bold()).foregroundStyle(AppTheme.green)
            }
            HStack {
                team(m.home, m.homeLogo); Spacer()
                VStack(spacing: 5) {
                    if let h = m.homeScore, let a = m.awayScore { Text("\(h) - \(a)").font(.system(size: 34, weight: .black, design: .rounded)) }
                    else if let date = m.date { Text(date, style: .time).font(.title2.bold()) }
                    if let elapsed = m.elapsed { Text("\(elapsed)′").font(.caption).foregroundStyle(AppTheme.green) }
                }
                Spacer(); team(m.away, m.awayLogo)
            }
        }
        .foregroundStyle(.white).padding(18)
        .background(LinearGradient(colors: [AppTheme.card, AppTheme.green.opacity(0.10)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 16)
    }

    private var followBar: some View {
        HStack(spacing: 10) {
            Button { Task { await toggleFollow() } } label: {
                Label(isFollowed ? "تتم متابعة المباراة" : "متابعة المباراة", systemImage: isFollowed ? "bell.fill" : "bell")
                    .font(.subheadline.bold()).foregroundStyle(isFollowed ? .black : .white)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(isFollowed ? AppTheme.green : AppTheme.card, in: Capsule())
            }.buttonStyle(.plain)
            Spacer()
            if let date = store.lastLiveUpdate { Text("تحديث \(date, style: .relative)").font(.caption2).foregroundStyle(AppTheme.muted) }
        }.padding(.horizontal, 16)
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case "تحليل 90+": insightView
        case "الأحداث": eventsView
        case "الإحصائيات": statsView
        case "التشكيلة": lineupsView
        case "المواجهات": h2hView
        default: overview
        }
    }

    private var overview: some View {
        let m = displayMatch
        return VStack(spacing: 12) {
            infoRow("الحالة", statusText(m)); infoRow("البطولة", m.league)
            if let date = m.date { infoRow("الموعد", date.formatted(date: .abbreviated, time: .shortened)) }
            infoRow("الأحداث المتاحة", "\(store.events.count)"); infoRow("التشكيلات", "\(store.lineups.count)"); infoRow("مواجهات سابقة", "\(store.h2h.count)")
            if let error = store.liveError {
                VStack(spacing: 8) {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                    Button { Task { await store.load(match) } } label: {
                        Label("إعادة تحميل بيانات المباراة", systemImage: "arrow.clockwise")
                            .font(.caption.bold()).foregroundStyle(AppTheme.green)
                    }
                }.frame(maxWidth: .infinity)
            }
        }.padding(16).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
    }

    private var insightView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("تحليل مبني على البيانات المتاحة فقط", systemImage: "sparkles").font(.headline).foregroundStyle(AppTheme.green)
            Text(factualSummary).font(.body).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
            if !keyFacts.isEmpty {
                VStack(spacing: 10) { ForEach(keyFacts, id: \.self) { fact in HStack(alignment: .top, spacing: 10) { Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.green); Text(fact).font(.subheadline); Spacer(minLength: 0) } } }
            }
            if !store.sectionErrors.isEmpty {
                Label("بعض مصادر بيانات هذه المباراة لم تستجب، لذلك التحليل يستخدم الأجزاء التي وصلت فقط.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.orange)
            }
            Text("90+ لا يخمّن أرقامًا غير موجودة في المصدر. إذا لم تتوفر الإحصائيات، يظهر ذلك بوضوح.").font(.caption).foregroundStyle(AppTheme.muted)
        }.padding(16).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
    }

    private var eventsView: some View {
        VStack(spacing: 0) {
            if store.events.isEmpty { sectionUnavailable("لا توجد أحداث منشورة", key: "events") }
            else { ForEach(Array(store.events.enumerated()), id: \.offset) { _, event in
                HStack { Text("\(event.time.elapsed ?? 0)′").foregroundStyle(AppTheme.green).frame(width: 42); VStack(alignment: .leading) { Text(event.player.name ?? event.team.name ?? "حدث").bold(); Text(event.detail ?? event.type ?? "").font(.caption).foregroundStyle(AppTheme.muted) }; Spacer() }.padding(12); Divider().overlay(Color.white.opacity(0.08))
            } }
        }.background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
    }

    private var statsView: some View {
        VStack(spacing: 12) {
            if store.stats.isEmpty { sectionUnavailable("الإحصائيات غير متاحة من المصدر", key: "stats") }
            else { ForEach(Array(store.stats.enumerated()), id: \.offset) { _, teamStats in
                VStack(alignment: .leading, spacing: 8) {
                    Text(teamStats.team.name ?? "فريق").font(.headline).foregroundStyle(AppTheme.green)
                    ForEach(Array(teamStats.statistics.enumerated()), id: \.offset) { _, stat in HStack { Text(stat.type ?? ""); Spacer(); Text(stat.value?.text ?? "0").bold() }.font(.subheadline) }
                }.padding(14).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
            } }
        }.padding(.horizontal, 16)
    }

    private var lineupsView: some View {
        VStack(spacing: 12) {
            if store.lineups.isEmpty { sectionUnavailable("التشكيلة غير منشورة حاليًا", key: "lineups") }
            else { ForEach(Array(store.lineups.enumerated()), id: \.offset) { _, lineup in
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(lineup.team.name ?? "فريق") • \(lineup.formation ?? "")").font(.headline).foregroundStyle(AppTheme.green)
                    ForEach(Array((lineup.startXI ?? []).enumerated()), id: \.offset) { _, slot in HStack { Text(slot.player.number.map(String.init) ?? "-").frame(width: 28); Text(slot.player.name ?? "لاعب"); Spacer(); Text(slot.player.pos ?? "").foregroundStyle(AppTheme.muted) }.font(.subheadline) }
                }.padding(14).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
            } }
        }.padding(.horizontal, 16)
    }

    private var h2hView: some View {
        VStack(spacing: 10) { if store.h2h.isEmpty { sectionUnavailable("لا توجد مواجهات سابقة منشورة", key: "h2h") } else { ForEach(store.h2h) { APICompactMatchCard(match: $0) } } }
    }

    private var factualSummary: String {
        let m = displayMatch
        if let home = m.homeScore, let away = m.awayScore {
            if home > away { return "\(m.home) متقدم على \(m.away) بنتيجة \(home)-\(away). التحليل أدناه يعتمد على أحداث وإحصائيات المباراة المنشورة من المصدر." }
            if away > home { return "\(m.away) متقدم على \(m.home) بنتيجة \(away)-\(home). التحليل أدناه يعتمد على أحداث وإحصائيات المباراة المنشورة من المصدر." }
            return "المباراة متعادلة \(home)-\(away). التحليل أدناه يعتمد على أحداث وإحصائيات المباراة المنشورة من المصدر."
        }
        return "المباراة لم تبدأ أو لا توجد نتيجة منشورة بعد. نعرض فقط المعلومات التي وصلت فعليًا من مصدر البيانات."
    }

    private var keyFacts: [String] {
        var facts: [String] = []
        let goals = store.events.filter { ($0.type ?? "").lowercased().contains("goal") }, cards = store.events.filter { ($0.type ?? "").lowercased().contains("card") }
        if !goals.isEmpty { facts.append("عدد أحداث الأهداف المنشورة: \(goals.count).") }
        if !cards.isEmpty { facts.append("عدد أحداث البطاقات المنشورة: \(cards.count).") }
        if store.lineups.count == 2 { facts.append("تشكيلة الفريقين متوفرة من المصدر.") }
        if !store.stats.isEmpty { facts.append("إحصائيات المباراة متوفرة لـ \(store.stats.count) فريق/طرف.") }
        if !store.h2h.isEmpty { facts.append("متوفر \(store.h2h.count) من المواجهات السابقة بين الفريقين.") }
        return facts
    }

    private func toggleFollow() async {
        var ids = Set(followedMatchIDs.split(separator: ",").map(String.init))
        if ids.contains(match.id) { ids.remove(match.id) }
        else {
            ids.insert(match.id)
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if granted { notificationsEnabled = true }
        }
        followedMatchIDs = ids.sorted().joined(separator: ",")
    }

    @ViewBuilder private func sectionUnavailable(_ fallback: String, key: String) -> some View {
        if let message = store.sectionErrors[key] {
            VStack(spacing: 10) {
                Image(systemName: "wifi.exclamationmark").font(.title2).foregroundStyle(.orange)
                Text("تعذر تحميل هذا القسم").font(.headline)
                Text(message).font(.caption).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
                Button { Task { await store.load(match) } } label: {
                    Label("إعادة المحاولة", systemImage: "arrow.clockwise").font(.caption.bold()).foregroundStyle(AppTheme.green)
                }
            }.frame(maxWidth: .infinity).padding(24)
        } else {
            unavailable(fallback)
        }
    }

    private func team(_ name: String, _ logo: String?) -> some View { VStack(spacing: 7) { RemoteBadge(url: logo).frame(width: 68, height: 68); Text(name).font(.subheadline.bold()).multilineTextAlignment(.center).lineLimit(2).frame(width: 105) } }
    private func infoRow(_ title: String, _ value: String) -> some View { HStack { Text(title).foregroundStyle(AppTheme.muted); Spacer(); Text(value).bold() } }
    private func unavailable(_ text: String) -> some View { Text(text).foregroundStyle(AppTheme.muted).frame(maxWidth: .infinity).padding(30) }

    private func statusText(_ m: APIPlusMatch) -> String {
        let status = m.status.uppercased()
        if APISportsStore.shared.isLive(status) { return m.elapsed.map { "مباشر • \($0)′" } ?? "مباشر" }
        switch status { case "FT": return "انتهت"; case "HT": return "بين الشوطين"; case "NS": return "لم تبدأ"; case "PST": return "مؤجلة"; case "CANC": return "ملغاة"; case "AET": return "وقت إضافي"; case "PEN": return "ركلات ترجيح"; default: return m.status.isEmpty ? "موعد" : m.status }
    }
}
