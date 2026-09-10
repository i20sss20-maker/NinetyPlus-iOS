"""Guarded last-stage integration; fail instead of silently omitting a feature."""
from pathlib import Path


def once(text, old, new, label):
    if new in text:
        if text.count(new) != 1 or old in text.replace(new, '', 1):
            raise RuntimeError('Premium duplicate anchor: ' + label)
        return text
    if text.count(old) != 1:
        raise RuntimeError('Premium missing/ambiguous anchor: ' + label)
    return text.replace(old, new, 1)


def apply_premium(root):
    root = Path(root)
    paths = ['Sources/Views/RootView.swift', 'Sources/Views/V2HomeView.swift',
             'Sources/Views/V2PowerCenter.swift', 'Sources/Views/V2MatchExperience.swift',
             'Sources/Views/V2Discovery.swift', 'Sources/Views/V2SavedLineupsView.swift',
             'Sources/Core/V2FeatureModels.swift', 'Sources/Core/LiveMatchActivity.swift', 'Sources/Views/V2Personalization.swift']
    originals = {p: (root / p).read_text(encoding='utf-8') for p in paths}
    output = dict(originals)
    p = paths[0]
    output[p] = once(output[p], '        .task { network.start() }', '''        .task { network.start() }
        .onReceive(APISportsStore.shared.$lastUpdated) { receivedAt in
            guard let receivedAt else { return }
            Task { @MainActor in
                // Published lastUpdated emits before refreshToday clears its error.
                await Task.yield()
                let api = APISportsStore.shared
                guard api.lastUpdated == receivedAt, api.error == nil else { return }
                PremiumFootballStore.shared.observe(api.today, receivedAt: receivedAt)
            }
        }''', 'snapshot observer')
    p = paths[1]
    output[p] = once(output[p], '                    header\n', '''                    header
                    NavigationLink { PremiumPulseView() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "waveform.path.ecg").font(.title2).foregroundStyle(AppTheme.green)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("90+ Pulse").font(.headline)
                                Text("الكرة الآن • وش فاتني؟ • موجز يومك").font(.caption).foregroundStyle(AppTheme.muted)
                            }
                            Spacer(); Image(systemName: "chevron.left")
                        }.foregroundStyle(.white).padding(16).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 20)).padding(.horizontal, 16)
                    }.buttonStyle(.plain).accessibilityIdentifier("home.pulse")
''', 'home Pulse entry')
    p = paths[2]
    output[p] = once(output[p], '                dataTruthCard\n', '''                NavigationLink { PremiumPulseView() } label: { featureCard("90+ Pulse وBrief", "المباريات والتغيّرات المرصودة وموجز يومك", "waveform.path.ecg") }
                    .accessibilityIdentifier("power.pulse")
                NavigationLink { PremiumGlobalSearch() } label: { featureCard("البحث الشامل", "لاعب ونادٍ وبطولة ومباراة وخبر في مكان واحد", "magnifyingglass.circle.fill") }
                    .accessibilityIdentifier("power.globalSearch")
                NavigationLink { PremiumReadingRoom() } label: { featureCard("غرفة الأخبار", "بحث ومصادر ومقالات محفوظة", "bookmark.fill") }
                    .accessibilityIdentifier("power.reading")
                Text("التذكير قبل المباراة يعمل محليًا على الجهاز. تحديث شاشة القفل يعمل مع وصول البيانات للتطبيق. تنبيهات الأهداف الحية أثناء إغلاقه تحتاج خدمة Push مهيأة، وليست مفعلة في هذه النسخة.").font(.caption).foregroundStyle(AppTheme.muted).padding(.horizontal, 16)
                dataTruthCard
''', 'power entries')
    p = paths[3]
    output[p] = once(output[p], '                followBar\n', '''                followBar
                if FixturePhase.isUpcoming(match.status), match.date != nil {
                    PremiumMatchReminderView(match: match)
                }
                NavigationLink { PremiumMatchExperience(seed: match, store: store) } label: {
                    Label("وش فاتني؟ • Live 360 • قصة المباراة", systemImage: "waveform.path.ecg")
                        .font(.subheadline.bold()).foregroundStyle(AppTheme.green).padding(12)
                }.accessibilityIdentifier("match.premium")
''', 'match premium controls')
    # Canonical loader must update Live Activities too; it previously bypassed that hook.
    old = '''                current = updated
                lastObserved = updated
            }
            let newEvents = detail.appEvents'''
    new = '''                current = updated
                lastObserved = updated
                if #available(iOS 16.1, *) { await LiveMatchActivityCoordinator.updateIfRunning(match: updated) }
            }
            let newEvents = detail.appEvents'''
    output[p] = once(output[p], old, new, 'canonical activity updates')
    p = paths[4]
    output[p] = once(output[p], '                    if let venue = team.venue {', '''                    NavigationLink { PremiumTeamIntelligence(homeID: team.id, homeName: team.name) } label: {
                        Label("Team DNA • مؤشر الفورمة", systemImage: "chart.bar.xaxis").font(.subheadline.bold()).foregroundStyle(AppTheme.green)
                    }.accessibilityIdentifier("team.dna")
                    if let venue = team.venue {''', 'team intelligence entry')
    output[p] = once(output[p], '''                VStack(spacing: 14) {
                    info("الجنسية", SportsArabic.country(player.nationality))''', '''                if !player.id.hasPrefix("tsdb:") { NavigationLink { PremiumPlayerRadar(player: player) } label: {
                    Label("Player Radar • معدلات كل 90", systemImage: "scope").font(.subheadline.bold()).foregroundStyle(AppTheme.green)
                        .frame(maxWidth: .infinity).padding(13).background(AppTheme.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                }.accessibilityIdentifier("player.radar") }
                VStack(spacing: 14) {
                    info("الجنسية", SportsArabic.country(player.nationality))''', 'player radar entry')
    p = paths[5]
    output[p] = once(output[p], '                    pitch\n', '                    PremiumInteractivePitch(draft: $draft, persist: persist)\n', 'interactive pitch')
    # Remove the now-unused old pitch view, using exact boundaries.
    start, end = '    private var pitch: some View {', '    private func restore() {'
    if start in output[p]:
        if output[p].count(start) != 1 or output[p].count(end) != 1:
            raise RuntimeError('Premium old pitch boundaries changed')
        a, b = output[p].index(start), output[p].index(end)
        if b <= a: raise RuntimeError('Premium pitch order changed')
        output[p] = output[p][:a] + output[p][b:]
    p = paths[6]
    output[p] = once(output[p], '    var updatedAt = Date()\n', '''    var updatedAt = Date()
    var captainIndex: Int? = nil
    var bench: [String]? = nil
''', 'compatible optional draft fields')
    output[p] = once(output[p], '        names.allSatisfy { $0.count <= 80 } && updatedAt.timeIntervalSince1970.isFinite', '''        names.allSatisfy { $0.count <= 80 } && updatedAt.timeIntervalSince1970.isFinite &&
        (captainIndex.map { (0..<11).contains($0) } ?? true) &&
        (bench.map { $0.count <= 9 && $0.allSatisfy { $0.count <= 80 } } ?? true)''', 'draft validation')
    old = '        return "90+ | \\(title) | \\(formation)\\nتشكيلة من إعداد المستخدم، وليست تشكيلة رسمية.\\n\\(players)"'
    new = '''        let captain = captainIndex.flatMap { names.indices.contains($0) ? names[$0] : nil } ?? "—"
        let substitutes = (bench ?? []).filter { !$0.isEmpty }.joined(separator: " • ")
        return "90+ | \\(title) | \\(formation)\\nتشكيلة من إعداد المستخدم، وليست تشكيلة رسمية.\\n\\(players)\\nالقائد: \\(captain)\\nالبدلاء: \\(substitutes)"'''
    output[p] = once(output[p], old, new, 'captain and substitutes sharing')
    p = paths[7]
    old = '''        .init(homeScore: match.homeScore, awayScore: match.awayScore,
              status: MatchLivePolicy.statusText(match.status, elapsed: match.elapsed).englishDigits,
              elapsed: match.elapsed, updatedAt: Date())'''
    new = '''        let hidden = UserDefaults.standard.bool(forKey: V2PreferenceKey.spoilerMode)
        return .init(homeScore: hidden ? nil : match.homeScore, awayScore: hidden ? nil : match.awayScore,
              status: hidden ? "النتيجة مخفية" : MatchLivePolicy.statusText(match.status, elapsed: match.elapsed).englishDigits,
              elapsed: hidden ? nil : match.elapsed, updatedAt: Date())'''
    output[p] = once(output[p], old, new, 'activity spoiler masking')
    p = paths[8]
    old = '                    NavigationLink { V2PowerCenterView() } label: { card("90+ 2.0", "الأدوات والتحليلات والإعدادات المتقدمة", "bolt.fill") }'
    output[p] = once(output[p], old, old + '.accessibilityIdentifier("more.power")', 'power navigation selector')
    for p, text in output.items():
        if text != originals[p]: (root / p).write_text(text, encoding='utf-8')
    print('Premium integration: Pulse/Brief, global search, reminders, Player Radar, saved news, Match 360, Team DNA, interactive lineup and canonical Activity updates')


if __name__ == '__main__':
    apply_premium(Path(__file__).resolve().parents[1])
