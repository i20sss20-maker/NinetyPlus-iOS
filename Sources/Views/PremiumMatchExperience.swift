import SwiftUI

struct PremiumMatchExperience: View {
    let seed: APIPlusMatch
    @ObservedObject var store: V2MatchCenterStore
    @StateObject private var premium = PremiumFootballStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(V2PreferenceKey.spoilerMode) private var spoiler = false
    @AppStorage(V2PreferenceKey.lowDataMode) private var lowData = false
    @State private var reveal = false
    @State private var visible = false
    @State private var capturedBaseline = false
    @State private var baseline: PremiumSeenMatch?
    @State private var tab = "وش فاتني؟"
    private var match: APIPlusMatch { store.current ?? seed }
    private var events: [PulseEvent] { PulseEvent.ordered(store.events.map(\.pulseEvent)) }
    private var unseen: [PulseEvent] { PulseEvent.newSince(events, previous: baseline.map { Set($0.eventIDs) }) }
    private var active: Bool { visible && scenePhase == .active }
    private var hidden: Bool { spoiler && !reveal }
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                PremiumMatchCard(match: match.pulseSnapshot, spoiler: hidden)
                SegmentBar(items: ["وش فاتني؟", "Live 360", "قصة المباراة"], selected: $tab)
                if hidden {
                    ContentUnavailableView("تفاصيل المباراة مخفية", systemImage: "eye.slash", description: Text("الأحداث والإحصائيات قد تكشف النتيجة."))
                    Button("إظهار لهذه الزيارة فقط") { reveal = true }
                } else {
                    if let date = store.lastLiveUpdate { Text("آخر استلام \(SportsDisplayDate.label(date, pattern: "d MMM، HH:mm"))").font(.caption).foregroundStyle(AppTheme.muted) }
                    if tab == "وش فاتني؟" { missed }
                    else if tab == "Live 360" { liveSummary }
                    else {
                        Text("قصة المباراة حسب الأحداث المنشورة").font(.headline)
                        timeline(events)
                        ShareLink(item: storyText) { Label("مشاركة الملخص النصي", systemImage: "square.and.arrow.up") }
                    }
                }
                Text("قد يتأخر المصدر أو يصحح الأحداث. هذه قراءة للبيانات المنشورة، وليست توقعًا أو تعليقًا مولدًا من أحداث غير متاحة.")
                    .font(.caption).foregroundStyle(AppTheme.muted).padding(.horizontal, 16)
                NavigationLink { PremiumTeamIntelligence(homeID: match.homeID, homeName: match.home, awayID: match.awayID, awayName: match.away) } label: {
                    Label("تحليل الفريقين والمواجهات", systemImage: "chart.bar.xaxis")
                }
            }.padding(.vertical, 16).padding(.bottom, 28)
        }.background(AppTheme.bg.ignoresSafeArea()).navigationTitle("المباراة 360").navigationBarTitleDisplayMode(.inline)
        .onAppear {
            visible = true
            if !capturedBaseline { baseline = premium.archive.seen[seed.id]; capturedBaseline = true }
        }
        .onDisappear {
            if !hidden, store.progress.state(.events).value != nil { premium.remember(matchID: seed.id, events: events) }
            visible = false; store.cancelPending()
        }
        .task(id: active) {
            guard active else { return }
            await store.load(seed)
            while !Task.isCancelled && active {
                guard let delay = MatchLivePolicy.interval(status: match.status, kickoff: match.date) else { return }
                do { try await Task.sleep(for: .seconds(lowData ? max(120, delay) : delay)) } catch { return }
                guard active, !Task.isCancelled else { return }
                await store.refreshLive(seed, sections: [.events, .stats, .lineups])
            }
        }
        .refreshable { await store.load(seed, force: true) }
        .accessibilityIdentifier("premium.match360")
    }
    private var missed: some View {
        VStack(spacing: 12) {
            Text(baseline == nil ? "ملخص الزيارة الأولى" : "الأحداث الجديدة مقارنة بآخر اطلاع").font(.headline)
            if let baseline { Text("اطلاعك السابق: \(SportsDisplayDate.label(baseline.seenAt, pattern: "d MMM، HH:mm"))").font(.caption).foregroundStyle(AppTheme.muted) }
            if baseline == nil { Text("ما عندنا زيارة سابقة نقارن بها؛ نعرض الأحداث المتاحة، ولا نعتبرها أحداثًا فاتتك.").font(.caption).foregroundStyle(AppTheme.muted) }
            timeline(baseline == nil ? events : unseen)
        }
    }
    private var liveSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("المشهد الحالي").font(.title3.bold())
            Text(MatchLivePolicy.summary(status: match.status, homeName: SportsArabic.team(match.home), awayName: SportsArabic.team(match.away), home: match.homeScore, away: match.awayScore))
            if store.progress.state(.events).value != nil {
                Text("من أحداث المصدر: \(events.filter(\.isRecordedGoal).count) هدف مسجل • \(events.filter(\.isRed).count) بطاقة حمراء")
                    .font(.caption).foregroundStyle(AppTheme.muted)
            } else { Text("لم تصل بيانات الأحداث بعد.").font(.caption).foregroundStyle(AppTheme.muted) }
            if store.progress.state(.events).errorMessage != nil { Text("تعذر تحديث الأحداث؛ الأعداد من آخر بيانات وصلت.").font(.caption).foregroundStyle(.orange) }
            Text("توزيع الأحداث المنشورة").font(.headline)
            Text("عدد الأحداث لكل فترة، وليس مؤشر ضغط أو زخم هجومي.").font(.caption).foregroundStyle(AppTheme.muted)
            ForEach(0..<9) { bucket in
                let count = events.filter { event in guard let minute = event.minute else { return false }; return min(minute / 15, 8) == bucket }.count
                HStack {
                    Text(bucket == 8 ? "120+" : "\(bucket*15)–\(bucket*15+14)").font(.caption).frame(width: 60)
                    GeometryReader { geometry in
                        Capsule().fill(AppTheme.green.opacity(0.7)).frame(width: geometry.size.width * Double(count) / Double(max(events.count, 1)))
                    }.frame(height: 8)
                    Text(String(count)).font(.caption.monospacedDigit()).frame(width: 30)
                }
            }
            ForEach(Array(store.stats.enumerated()), id: \.offset) { _, team in
                Text(SportsArabic.team(team.team.name ?? "فريق")).font(.headline)
                ForEach(Array(team.statistics.enumerated()), id: \.offset) { _, item in
                    HStack { Text(item.type ?? "إحصائية"); Spacer(); Text(statText(item.value)).monospacedDigit() }.font(.caption)
                }
            }
            if store.stats.isEmpty { Text("لا توجد إحصائيات منشورة متاحة في هذه الزيارة.").font(.caption).foregroundStyle(AppTheme.muted) }
        }.padding(16).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20)).padding(.horizontal, 16)
    }
    private func timeline(_ values: [PulseEvent]) -> some View {
        VStack(spacing: 12) {
            if values.isEmpty {
                if store.progress.state(.events).isLoading { ProgressView() }
                else { Text(store.progress.state(.events).errorMessage == nil ? "لا توجد أحداث جديدة متاحة لهذا العرض." : "تعذر جلب الأحداث؛ اسحب للتحديث.").font(.caption).foregroundStyle(AppTheme.muted) }
            }
            ForEach(Array(values.prefix(150))) { event in
                HStack(alignment: .top, spacing: 12) {
                    Text(event.clock).font(.caption.bold()).monospacedDigit().foregroundStyle(AppTheme.green).frame(width: 55)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(event.player.isEmpty ? event.team : event.player).font(.subheadline.bold())
                        Text("\(SportsArabic.eventType(event.type)) • \(event.detail)").font(.caption).foregroundStyle(AppTheme.muted)
                        if !event.team.isEmpty { Text(event.team).font(.caption2).foregroundStyle(AppTheme.muted) }
                    }
                    Spacer(minLength: 0)
                }.padding(13).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 16))
            }
            if values.count > 150 { Text("يُعرض أول 150 حدثًا من \(values.count).").font(.caption) }
        }.padding(.horizontal, 16)
    }
    private func statText(_ value: APIStatValue?) -> String {
        guard let value else { return "—" }
        if case .null = value { return "—" }
        let text = value.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "—" : text.englishDigits
    }
    private var storyText: String {
        let header = V2Share.match(match, hidingScore: hidden)
        guard !hidden else { return header }
        let timeline = events.prefix(40).map { "\($0.clock) \(SportsArabic.eventType($0.type)) • \($0.player) • \($0.detail)" }.joined(separator: "\n")
        return "\(header)\nالأحداث المنشورة من المصدر (حتى 40 حدثًا):\n\(timeline)".englishDigits
    }
}
