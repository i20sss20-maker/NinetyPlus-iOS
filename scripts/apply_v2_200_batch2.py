from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
def read(p): return (ROOT / p).read_text(encoding='utf-8')
def write(p,s): (ROOT / p).write_text(s, encoding='utf-8')

# Home: pinned matches rise above normal priority without replacing personal ranking.
p='Sources/Views/V2HomeView.swift'; s=read(p)
if 'PinnedMatchStore.contains(match.id) ? -100' not in s:
    old='''    private func priority(_ match: APIPlusMatch) -> Int {
        let followed = match.homeID.map { teams.contains($0) } == true || match.awayID.map { teams.contains($0) } == true
'''
    new='''    private func priority(_ match: APIPlusMatch) -> Int {
        if PinnedMatchStore.contains(match.id) { return -100 }
        let followed = match.homeID.map { teams.contains($0) } == true || match.awayID.map { teams.contains($0) } == true
'''
    if old not in s: raise RuntimeError('home priority anchor missing')
    s=s.replace(old,new,1)
write(p,s)

# Match list: My Scores alias plus compact context labels.
p='Sources/Views/V2MatchExperience.swift'; s=read(p)
if 'case "مبارياتي"' not in s:
    s=s.replace('''        case "متابعاتي":
            let ids = Set(SavedFavoriteIDs.parse(favoriteTeamIDs))
            return matches.filter { ($0.homeID.map(ids.contains) ?? false) || ($0.awayID.map(ids.contains) ?? false) }
''','''        case "متابعاتي", "مبارياتي":
            let ids = Set(SavedFavoriteIDs.parse(favoriteTeamIDs))
            let followedMatches = Set(SavedFavoriteIDs.parse(UserDefaults.standard.string(forKey: "followedMatchIDs") ?? ""))
            return matches.filter { followedMatches.contains($0.id) || ($0.homeID.map(ids.contains) ?? false) || ($0.awayID.map(ids.contains) ?? false) }
''',1)
    s=s.replace('''SegmentBar(items: ["الكل", "مباشر", "القادمة", "المنتهية", "متابعاتي", "مثبتة"], selected: $filter)''','''SegmentBar(items: ["الكل", "مباشر", "القادمة", "المنتهية", "مبارياتي", "مثبتة"], selected: $filter)''',1)

# Event filtering inside match center.
if '@State private var eventFilter = "الكل"' not in s:
    state='    @State private var tab = "نظرة عامة"\n'
    if state not in s: raise RuntimeError('match tab state anchor missing')
    s=s.replace(state,state+'    @State private var eventFilter = "الكل"\n',1)
    view_anchor='''    private var eventsView: some View {
        VStack(spacing: 0) {
'''
    if view_anchor not in s: raise RuntimeError('events view anchor missing')
    filtered='''    private var filteredEvents: [APIEventItem] {
        switch eventFilter {
        case "أهداف": return store.events.filter { ($0.type ?? "").lowercased().contains("goal") }
        case "بطاقات": return store.events.filter { ($0.type ?? "").lowercased().contains("card") }
        case "تبديلات": return store.events.filter { ($0.type ?? "").lowercased().contains("subst") }
        default: return store.events
        }
    }

'''
    s=s.replace(view_anchor,filtered+'''    private var eventsView: some View {
        VStack(spacing: 10) {
            SegmentBar(items: ["الكل", "أهداف", "بطاقات", "تبديلات"], selected: $eventFilter)
''',1)
    s=s.replace('ForEach(store.events.indices, id: \\.self)', 'ForEach(filteredEvents.indices, id: \\.self)', 1)
    s=s.replace('let event = store.events[index]', 'let event = filteredEvents[index]', 1)
write(p,s)

# Notification runtime: honor granular preferences and spoiler mode.
p='Sources/Views/V2MatchExperience.swift'; s=read(p)
if 'V2FeaturePreferences.notifyGoals' not in s:
    marker='''        let title: String
        switch notice {
        case .started: title = "بدأت المباراة"
        case .scoreChanged: title = "تغيرت النتيجة"
        case .finished: title = "انتهت المباراة"
        }
'''
    replacement='''        let title: String
        switch notice {
        case .started:
            guard UserDefaults.standard.object(forKey: V2FeaturePreferences.notifyKickoff) as? Bool ?? true else { return }
            title = "بدأت المباراة"
        case .scoreChanged:
            guard UserDefaults.standard.object(forKey: V2FeaturePreferences.notifyGoals) as? Bool ?? true else { return }
            title = "تغيرت النتيجة"
        case .finished:
            title = "انتهت المباراة"
        }
'''
    if marker not in s: raise RuntimeError('notification switch anchor missing')
    s=s.replace(marker,replacement,1)
    old='''        if let home = updated.homeScore, let away = updated.awayScore {
            body = "\\(SportsArabic.team(updated.home)) \\(home) - \\(away) \\(SportsArabic.team(updated.away))"
        }
'''
    new='''        let hideScore = UserDefaults.standard.bool(forKey: V2FeaturePreferences.spoilerMode)
        if !hideScore, let home = updated.homeScore, let away = updated.awayScore {
            body = "\\(SportsArabic.team(updated.home)) \\(home) - \\(away) \\(SportsArabic.team(updated.away))"
        }
'''
    if old in s: s=s.replace(old,new,1)
write(p,s)

print('Applied 90+ 200-feature batch 2: pinned priority, My Scores, event filters, granular notifications and spoiler-safe alerts')
