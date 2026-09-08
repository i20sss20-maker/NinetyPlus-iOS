import SwiftUI

struct PremiumPulseView: View {
    @StateObject private var premium = PremiumFootballStore.shared
    @StateObject private var api = APISportsStore.shared
    @AppStorage("favoriteTeamIDs") private var teamIDs = ""
    @AppStorage("ninetyplus.favoriteLeagueIDs") private var leagueIDs = ""
    @AppStorage("followedMatchIDs") private var matchIDs = ""
    @AppStorage(V2PreferenceKey.spoilerMode) private var spoiler = false
    @AppStorage("ninetyplus.pulse.personalOnly") private var personal = false
    @State private var section = "الآن"
    @State private var phase = "الكل"
    @State private var query = ""
    private var preferences: PulsePreferences {
        let leagues = SavedFavoriteIDs.parse(leagueIDs).map { id in
            LeagueOption.featured.first { $0.id == id }?.apiFootballID ?? id
        }
        return .init(teams: Set(SavedFavoriteIDs.parse(teamIDs)), leagues: Set(leagues), matches: Set(SavedFavoriteIDs.parse(matchIDs)))
    }
    private var matches: [PulseFixture] {
        let ranked = PulseRules.ranked(premium.archive.latest.values, preferences: preferences, now: Date())
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return ranked.filter { m in
            let chosen = !personal || preferences.follows(m)
            let filtered = phase == "الكل" || (phase == "مباشر" && m.isLive) || (phase == "القادمة" && m.isUpcoming) || (phase == "المنتهية" && m.isFinished)
            return chosen && filtered && (search.isEmpty || [m.home, m.away, m.league].contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                TopBar(title: "90+ Pulse", subtitle: "الكرة الآن • حسب آخر البيانات المستلمة")
                SegmentBar(items: ["الآن", "وش فاتني؟", "يومي"], selected: $section)
                Toggle("متابعاتي فقط", isOn: $personal).padding(.horizontal, 18).accessibilityIdentifier("pulse.personal")
                receipt
                if let warning = premium.storageWarning { Text(warning).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
                if section == "وش فاتني؟" { brief }
                else {
                    if section == "يومي" { daily }
                    TextField("ابحث في الأندية والبطولات", text: $query).textFieldStyle(.roundedBorder).padding(.horizontal, 16)
                    SegmentBar(items: ["الكل", "مباشر", "القادمة", "المنتهية"], selected: $phase)
                    if matches.isEmpty {
                        ContentUnavailableView(personal ? "لا توجد مباريات تطابق متابعاتك" : "لا توجد مباريات محفوظة تطابق الاختيار", systemImage: "soccerball", description: Text("غيّر الفلتر أو عطّل متابعاتي فقط. سحب الصفحة يطلب تحديث البيانات."))
                    }
                    ForEach(matches) { match in
                        NavigationLink { V2MatchCenterView(match: match.appMatch) } label: {
                            PremiumMatchCard(match: match, spoiler: spoiler, followed: preferences.follows(match))
                        }.buttonStyle(.plain)
                    }
                }
                NavigationLink { PremiumReadingRoom() } label: { Label("غرفة الأخبار والمحفوظات", systemImage: "bookmark.fill") }
                    .accessibilityIdentifier("pulse.reading")
            }.padding(.vertical, 12).padding(.bottom, 28)
        }
        .background(AppTheme.bg.ignoresSafeArea()).navigationTitle("Pulse").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("pulse.screen")
        .refreshable { await api.refreshToday(force: true) }
    }
    private var receipt: some View {
        VStack(alignment: .leading, spacing: 5) {
            if premium.archive.latest.receivedAt != .distantPast {
                Text("آخر استلام: \(SportsDisplayDate.label(premium.archive.latest.receivedAt, pattern: "d MMM، HH:mm"))")
                Text("قد تكون البيانات مخزنة لدى المصدر. الحالات والنتائج أدناه مرتبطة بآخر استلام، وليست ضمانًا للتحديث اللحظي.")
            } else { Text("تظهر البيانات عند اكتمال تحديث المباريات. لم نضع نتائج تجريبية بدلًا عنها.") }
            if api.error != nil { Text("تعذر التحديث الآن؛ البيانات المحفوظة باقية.").foregroundStyle(.orange) }
        }.font(.caption).foregroundStyle(AppTheme.muted).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18)
    }
    private var brief: some View {
        let changes = premium.archive.unread(preferences: preferences, personalOnly: personal)
        return VStack(spacing: 14) {
            Text("تغيّرات رصدها التطبيق منذ آخر اطلاع. لا يرصد أحداثًا جديدة أثناء إغلاقه، وقد تشمل التغيّرات تصحيحًا من المصدر.")
                .font(.caption).foregroundStyle(AppTheme.muted)
            if changes.isEmpty { ContentUnavailableView("لا توجد تغيّرات جديدة مرصودة", systemImage: "checkmark.circle") }
            ForEach(changes) { change in
                NavigationLink { V2MatchCenterView(match: change.match.appMatch) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(spoiler ? "تحديث محفوظ للمباراة" : change.title).font(.headline).foregroundStyle(AppTheme.green)
                        Text("\(change.match.home) × \(change.match.away)").font(.subheadline.bold())
                        Text(change.match.scoreText(hidden: spoiler)).font(.title3.bold()).monospacedDigit()
                        Text("رُصد \(SportsDisplayDate.label(change.observedAt, pattern: "d MMM، HH:mm"))").font(.caption).foregroundStyle(AppTheme.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(15).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(.plain)
            }
            Button("تم الاطلاع على جميع التغيّرات") { premium.markRead() }.disabled(changes.isEmpty).accessibilityIdentifier("pulse.markRead")
        }.padding(.horizontal, 16)
    }
    private var daily: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("موجز يومك").font(.title3.bold())
            Text("\(matches.count) مباراة تطابق اختيارك")
            if !spoiler {
                Text("\(matches.filter(\.isLive).count) جارية • \(matches.filter(\.isUpcoming).count) قادمة • \(matches.filter(\.isFinished).count) منتهية")
            }
            Text("الترتيب: المتابعات أولًا، ثم الجاري والمتأخر من المباريات والمواعيد القريبة. الترتيب ليس توقعًا للنتائج.")
                .font(.caption).foregroundStyle(AppTheme.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20)).padding(.horizontal, 16)
    }
}

struct PremiumMatchCard: View {
    let match: PulseFixture
    let spoiler: Bool
    var followed = false
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(match.league).font(.caption).lineLimit(1)
                Spacer()
                if followed { Image(systemName: "star.fill").foregroundStyle(AppTheme.green).accessibilityLabel("من متابعاتك") }
            }.foregroundStyle(AppTheme.muted)
            HStack {
                Text(match.home).frame(maxWidth: .infinity)
                Text(match.scoreText(hidden: spoiler)).font(.title3.bold()).monospacedDigit().environment(\.layoutDirection, .leftToRight)
                Text(match.away).frame(maxWidth: .infinity)
            }.font(.subheadline.bold()).multilineTextAlignment(.center)
            HStack {
                Text(spoiler && !match.isUpcoming ? "تفاصيل المباراة مخفية" : MatchLivePolicy.statusText(match.status, elapsed: match.elapsed))
                Spacer()
                if let date = match.kickoff { Text(SportsDisplayDate.label(date, pattern: "d MMM HH:mm")) }
            }.font(.caption2).foregroundStyle(AppTheme.muted)
        }.foregroundStyle(.white).padding(16).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 20)).padding(.horizontal, 16)
    }
}

struct PremiumReadingRoom: View {
    @StateObject private var editorial = EditorialStore.shared
    @StateObject private var premium = PremiumFootballStore.shared
    @State private var tab = "الأخبار"
    @State private var query = ""
    @State private var source = "الكل"
    private var all: [PremiumArticle] {
        if tab == "المحفوظة" { return premium.archive.savedArticles }
        return (tab == "الانتقالات" ? editorial.transfers : editorial.news).compactMap(\.premiumArticle)
    }
    private var sources: [String] { ["الكل"] + Set(all.map(\.source)).sorted() }
    private var articles: [PremiumArticle] {
        all.filter { (source == "الكل" || $0.source == source) && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }
    }
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                TopBar(title: "غرفة الأخبار", subtitle: "مصادر واضحة • حفظ محلي • بحث")
                SegmentBar(items: ["الأخبار", "الانتقالات", "المحفوظة"], selected: $tab)
                TextField("ابحث في العناوين", text: $query).textFieldStyle(.roundedBorder).padding(.horizontal, 16)
                Picker("المصدر", selection: $source) { ForEach(sources, id: \.self) { Text($0).tag($0) } }.pickerStyle(.menu)
                Text("الحفظ يشمل العنوان والمصدر والرابط، وليس نسخة من المقال الكامل. قراءة المقال الأصلي تحتاج اتصالًا.")
                    .font(.caption).foregroundStyle(AppTheme.muted).padding(.horizontal, 16)
                if let warning = premium.storageWarning { Text(warning).font(.caption).foregroundStyle(.orange) }
                if editorial.isLoading { ProgressView() }
                if articles.isEmpty { ContentUnavailableView("لا توجد أخبار تطابق الاختيار", systemImage: "bookmark") }
                ForEach(articles) { article in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(article.title).font(.headline)
                        Text("\(article.source) • \(SportsDisplayDate.label(article.publishedAt, pattern: "d MMM، HH:mm"))")
                            .font(.caption).foregroundStyle(AppTheme.muted)
                        if tab == "الانتقالات" { Text(article.provenance).font(.caption2).foregroundStyle(.orange) }
                        HStack {
                            if let url = PremiumArticle.safeURL(article.url) { InAppWebLink(url: url) { Label("المصدر الأصلي", systemImage: "safari") } }
                            Spacer()
                            Button { premium.toggle(article) } label: {
                                let saved = premium.archive.savedArticles.contains { $0.id == article.id }
                                Label(saved ? "محفوظ" : "حفظ", systemImage: saved ? "bookmark.fill" : "bookmark")
                            }
                        }.font(.caption.bold()).foregroundStyle(AppTheme.green)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20)).padding(.horizontal, 16)
                }
            }.padding(.bottom, 30)
        }.background(AppTheme.bg.ignoresSafeArea()).navigationTitle("الأخبار").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .onChange(of: tab) { _, _ in source = "الكل" }
        .onChange(of: sources) { _, values in if !values.contains(source) { source = "الكل" } }
        .task { if tab != "المحفوظة" { await editorial.refreshIfStale(maxAge: 300) } }
        .refreshable { await editorial.refresh() }
        .accessibilityIdentifier("premium.reading.screen")
    }
}
