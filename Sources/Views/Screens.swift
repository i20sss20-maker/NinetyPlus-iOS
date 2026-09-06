import SwiftUI
import UserNotifications

struct MatchesView: View {
    @State private var segment = "الكل"
    @StateObject private var store = SportsStore.shared

    private var filtered: [LiveMatch] {
        switch segment {
        case "مباشر": return store.matches.filter { !$0.status.isEmpty && !$0.status.lowercased().contains("not started") && $0.homeScore == nil }
        case "المنتهية": return store.matches.filter { $0.homeScore != nil && $0.awayScore != nil }
        case "القادمة": return store.matches.filter { $0.homeScore == nil && $0.awayScore == nil }
        default: return store.matches
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    TopBar(title: "المباريات")
                    SegmentBar(items: ["الكل", "مباشر", "القادمة", "المنتهية"], selected: $segment)
                    if store.isLoading && store.matches.isEmpty {
                        ProgressView("جاري تحديث المباريات...").tint(AppTheme.green).foregroundStyle(.white).padding(.top, 70)
                    } else if filtered.isEmpty {
                        empty
                    } else {
                        ForEach(filtered) { match in
                            NavigationLink { MatchDetailView(match: match) } label: { matchCard(match) }.buttonStyle(.plain)
                        }
                    }
                }.padding(.bottom, 24)
            }
            .refreshable { await store.refresh() }
            .task {
                if store.matches.isEmpty { await store.refresh() }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    await store.refresh()
                }
            }
            .background(AppTheme.bg.ignoresSafeArea())
        }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "soccerball").font(.system(size: 44)).foregroundStyle(AppTheme.green)
            Text("لا توجد مباريات في هذا القسم الآن").foregroundStyle(AppTheme.muted)
        }.padding(.top, 70)
    }

    private func matchCard(_ m: LiveMatch) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(m.league).font(.caption).foregroundStyle(AppTheme.muted).lineLimit(1)
                Spacer()
                if !m.status.isEmpty { Text(m.status).font(.caption2.bold()).foregroundStyle(AppTheme.green) }
            }
            HStack(spacing: 14) {
                team(name: m.home, badge: m.homeBadge)
                Spacer()
                VStack(spacing: 5) {
                    if let hs = m.homeScore, let ascore = m.awayScore { Text("\(hs) - \(ascore)").font(.title2.bold()) }
                    else { Text(m.time).font(.headline).foregroundStyle(AppTheme.green) }
                    Text(m.homeScore == nil ? "موعد المباراة" : "النتيجة").font(.caption2).foregroundStyle(AppTheme.muted)
                }
                Spacer()
                team(name: m.away, badge: m.awayBadge)
            }
        }
        .padding(16).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
    }

    private func team(name: String, badge: String?) -> some View {
        VStack(spacing: 6) {
            RemoteBadge(url: badge).frame(width: 44, height: 44)
            Text(name).font(.caption.bold()).multilineTextAlignment(.center).lineLimit(2).frame(maxWidth: 95)
        }
    }
}

struct MatchDetailView: View {
    let match: LiveMatch
    @StateObject private var detail = MatchInsightStore()
    @State private var tab = "الإحصائيات"

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                scoreHeader
                SegmentBar(items: ["الإحصائيات", "الأحداث", "التشكيلة"], selected: $tab)
                if detail.loading { ProgressView("جاري جلب التفاصيل...").tint(AppTheme.green).padding(30) }
                else {
                    switch tab {
                    case "الأحداث": timelineSection
                    case "التشكيلة": lineupSection
                    default: statsSection
                    }
                }
            }.padding(.vertical, 14)
        }
        .navigationTitle("تفاصيل المباراة")
        .navigationBarTitleDisplayMode(.inline)
        .background(AppTheme.bg.ignoresSafeArea())
        .task { await detail.load(eventID: match.id) }
    }

    private var scoreHeader: some View {
        VStack(spacing: 10) {
            Text(match.league).font(.headline).foregroundStyle(AppTheme.muted)
            HStack(spacing: 20) {
                club(match.home, match.homeBadge)
                Spacer()
                VStack(spacing: 6) {
                    if let hs = match.homeScore, let ascore = match.awayScore { Text("\(hs) - \(ascore)").font(.system(size: 38, weight: .black)) }
                    else { Text(match.time).font(.title2.bold()).foregroundStyle(AppTheme.green) }
                    if !match.status.isEmpty { Text(match.status).font(.caption).foregroundStyle(AppTheme.green) }
                }
                Spacer()
                club(match.away, match.awayBadge)
            }
        }
        .padding(20).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22)).padding(.horizontal, 16)
    }

    private var statsSection: some View {
        VStack(spacing: 0) {
            if detail.stats.isEmpty { unavailable("لا توجد إحصائيات منشورة لهذه المباراة") }
            else {
                ForEach(detail.stats) { stat in
                    VStack(spacing: 7) {
                        HStack { Text(stat.home).bold(); Spacer(); Text(arabicStat(stat.name)).font(.caption).foregroundStyle(AppTheme.muted); Spacer(); Text(stat.away).bold() }
                        Divider().overlay(Color.white.opacity(0.08))
                    }.padding(.horizontal, 18).padding(.vertical, 9)
                }
            }
        }.background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
    }

    private var timelineSection: some View {
        VStack(spacing: 0) {
            if detail.timeline.isEmpty { unavailable("لا توجد أحداث تفصيلية منشورة لهذه المباراة") }
            else {
                ForEach(detail.timeline) { event in
                    HStack(spacing: 12) {
                        Text("\(event.intTime ?? "-")′").font(.headline).foregroundStyle(AppTheme.green).frame(width: 42)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.strPlayer ?? event.strTeam ?? "حدث").font(.subheadline.bold())
                            Text(event.strTimelineDetail ?? event.strTimeline ?? "").font(.caption).foregroundStyle(AppTheme.muted)
                        }
                        Spacer()
                        Image(systemName: timelineIcon(event.strTimeline ?? "")).foregroundStyle(AppTheme.green)
                    }.padding(14)
                    Divider().overlay(Color.white.opacity(0.08))
                }
            }
        }.background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
    }

    private var lineupSection: some View {
        VStack(spacing: 14) {
            if detail.lineup.isEmpty { unavailable("التشكيلة غير متاحة من المصدر لهذه المباراة") }
            else {
                lineupTeam(title: match.home, home: true)
                lineupTeam(title: match.away, home: false)
            }
        }.padding(.horizontal, 16)
    }

    private func lineupTeam(title: String, home: Bool) -> some View {
        let players = detail.lineup.filter { ($0.strHome == "Yes") == home }
        return VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundStyle(AppTheme.green)
            ForEach(players) { player in
                HStack(spacing: 10) {
                    AsyncImage(url: player.strCutout.flatMap(URL.init(string:))) { phase in
                        if case .success(let img) = phase { img.resizable().scaledToFit() }
                        else { Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(AppTheme.soft) }
                    }.frame(width: 38, height: 38)
                    VStack(alignment: .leading) {
                        Text(player.strPlayer ?? "لاعب").font(.subheadline.bold())
                        Text("\(player.intSquadNumber ?? "-") • \(player.strPosition ?? "")\(player.strSubstitute == "Yes" ? " • بديل" : "")")
                            .font(.caption).foregroundStyle(AppTheme.muted)
                    }
                    Spacer()
                }
            }
        }.padding(16).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private func unavailable(_ text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "info.circle").font(.title2).foregroundStyle(AppTheme.green)
            Text(text).font(.subheadline).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(28)
    }

    private func club(_ name: String, _ badge: String?) -> some View {
        VStack(spacing: 8) { RemoteBadge(url: badge).frame(width: 66, height: 66); Text(name).font(.headline).multilineTextAlignment(.center).frame(maxWidth: 105) }
    }

    private func arabicStat(_ value: String) -> String {
        let map = ["Shots on Goal":"تسديدات على المرمى", "Shots off Goal":"تسديدات خارج المرمى", "Total Shots":"إجمالي التسديدات", "Blocked Shots":"تسديدات محجوبة", "Possession":"الاستحواذ", "Corners":"الركنيات", "Fouls":"الأخطاء", "Yellow Cards":"بطاقات صفراء", "Red Cards":"بطاقات حمراء", "Passes":"التمريرات"]
        return map[value] ?? value
    }

    private func timelineIcon(_ type: String) -> String {
        let t = type.lowercased()
        if t.contains("goal") { return "soccerball" }
        if t.contains("card") { return "rectangle.fill" }
        if t.contains("subst") { return "arrow.left.arrow.right" }
        return "circle.fill"
    }
}

struct NewsView: View {
    @StateObject private var store = SportsStore.shared
    @State private var query = ""
    private var items: [RealArticle] { query.isEmpty ? store.news : store.news.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.source.localizedCaseInsensitiveContains(query) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    TopBar(title: "الأخبار")
                    if items.isEmpty && !store.isLoading { Text("لا توجد نتائج").foregroundStyle(AppTheme.muted).padding(.top, 60) }
                    ForEach(items) { item in articleCard(item) }
                }.padding(.bottom, 24)
            }
            .searchable(text: $query, prompt: "ابحث في الأخبار")
            .refreshable { await store.refresh() }
            .task { if store.news.isEmpty { await store.refresh() } }
            .background(AppTheme.bg.ignoresSafeArea())
        }
    }

    private func articleCard(_ item: RealArticle) -> some View {
        Link(destination: item.url ?? URL(string: "https://news.google.com")!) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(AppTheme.green)
                    Text(item.source.isEmpty ? "مصدر إخباري" : item.source).font(.caption.bold()).foregroundStyle(AppTheme.green)
                    Spacer()
                    Text(item.date, style: .relative).font(.caption2).foregroundStyle(AppTheme.muted)
                }
                Text(item.title).font(.headline).foregroundStyle(.white).multilineTextAlignment(.leading)
                HStack { Text("فتح المصدر الأصلي").font(.caption).foregroundStyle(AppTheme.muted); Spacer(); Image(systemName: "arrow.up.right.square").foregroundStyle(AppTheme.muted) }
            }
            .padding(15).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
        }
    }
}

struct TransfersView: View {
    @StateObject private var store = SportsStore.shared
    @State private var query = ""
    private var items: [RealArticle] { query.isEmpty ? store.transfers : store.transfers.filter { $0.title.localizedCaseInsensitiveContains(query) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    TopBar(title: "مركز الانتقالات")
                    Text("تجميع انتقالات من مصادر فعلية. لا نضع نسبة تأكيد إلا إذا كانت لها آلية تحقق مستقلة.")
                        .font(.caption).foregroundStyle(AppTheme.muted).padding(.horizontal, 16)
                    ForEach(items) { item in
                        Link(destination: item.url ?? URL(string: "https://news.google.com")!) {
                            VStack(alignment: .leading, spacing: 9) {
                                HStack {
                                    Text(item.source.isEmpty ? "مصدر إخباري" : item.source).font(.caption.bold()).foregroundStyle(AppTheme.green)
                                    Spacer(); Text(item.date, style: .relative).font(.caption2).foregroundStyle(AppTheme.muted)
                                }
                                Text(item.title).font(.headline).foregroundStyle(.white).multilineTextAlignment(.leading)
                                Label("فتح المصدر", systemImage: "link").font(.caption).foregroundStyle(AppTheme.muted)
                            }
                            .padding(15).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
                        }
                    }
                }.padding(.bottom, 24)
            }
            .searchable(text: $query, prompt: "ابحث في الانتقالات")
            .refreshable { await store.refresh() }
            .task { if store.transfers.isEmpty { await store.refresh() } }
            .background(AppTheme.bg.ignoresSafeArea())
        }
    }
}

struct ProfileView: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("favoriteLeague") private var favoriteLeague = "الدوري السعودي"
    @AppStorage("favoriteTeamIDs") private var favoriteTeamIDs = ""
    @State private var notificationStatus = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("90+") {
                    HStack { BrandLogo(); Spacer(); VStack(alignment: .trailing) { Text("90+ iOS").bold(); Text("بيانات مباشرة").font(.caption).foregroundStyle(.secondary) } }
                }
                Section("البطولات والفرق") {
                    NavigationLink { LeaguesView() } label: { Label("ترتيب البطولات", systemImage: "trophy.fill") }
                    HStack { Label("الفرق المفضلة", systemImage: "star.fill"); Spacer(); Text("\(favoriteCount)").foregroundStyle(.secondary) }
                }
                Section("التفضيلات") {
                    Toggle("السماح بالإشعارات", isOn: Binding(get: { notificationsEnabled }, set: { newValue in notificationsEnabled = newValue; if newValue { Task { await requestNotifications() } } }))
                    if !notificationStatus.isEmpty { Text(notificationStatus).font(.caption).foregroundStyle(.secondary) }
                    Picker("الدوري المفضل", selection: $favoriteLeague) {
                        ForEach(LeagueOption.featured) { Text($0.arabicName).tag($0.arabicName) }
                    }
                }
                Section("المصادر") {
                    Label("المباريات والجداول: TheSportsDB", systemImage: "soccerball")
                    Label("الأخبار: Google News RSS", systemImage: "newspaper")
                    Text("التطبيق لا يخترع نتائج أو تشكيلات أو نسب انتقالات. العناصر غير المتاحة من المصدر تظهر كغير متاحة.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("التطبيق") {
                    HStack { Text("الإصدار"); Spacer(); Text("1.0").foregroundStyle(.secondary) }
                    Link(destination: URL(string: "https://www.thesportsdb.com")!) { Label("مزود بيانات المباريات", systemImage: "link") }
                }
            }
            .scrollContentBackground(.hidden).background(AppTheme.bg).navigationTitle("المزيد")
        }
    }

    private var favoriteCount: Int { favoriteTeamIDs.split(separator: ",").count }

    @MainActor private func requestNotifications() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            notificationStatus = granted ? "تم السماح بالإشعارات على الجهاز" : "لم يتم السماح بالإشعارات من النظام"
            if !granted { notificationsEnabled = false }
        } catch {
            notificationStatus = "تعذر طلب إذن الإشعارات"
            notificationsEnabled = false
        }
    }
}
