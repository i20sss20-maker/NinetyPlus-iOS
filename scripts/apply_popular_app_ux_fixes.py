from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def read(path): return (ROOT / path).read_text(encoding='utf-8')
def write(path, text): (ROOT / path).write_text(text, encoding='utf-8')

path='Sources/Views/V2MatchExperience.swift'
s=read(path)
if '@AppStorage("favoriteTeamIDs") private var favoriteTeamIDs = ""' not in s:
    s=s.replace('    @State private var retryID = 0\n','    @State private var retryID = 0\n    @AppStorage("favoriteTeamIDs") private var favoriteTeamIDs = ""\n',1)
if 'private var favoriteTeams: Set<String>' not in s:
    s=s.replace('    private var matches: [APIPlusMatch] { hasValue ? (resource.value ?? []) : [] }\n','    private var matches: [APIPlusMatch] { hasValue ? (resource.value ?? []) : [] }\n    private var favoriteTeams: Set<String> { Set(SavedFavoriteIDs.parse(favoriteTeamIDs)) }\n',1)
s=s.replace('        case "مباشر": return matches.filter { store.isLive($0.status) }\n','        case "متابعاتي": return matches.filter { match in\n            match.homeID.map { favoriteTeams.contains($0) } == true || match.awayID.map { favoriteTeams.contains($0) } == true\n        }\n        case "مباشر": return matches.filter { store.isLive($0.status) }\n',1)
s=s.replace('            .sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }','            .sorted { lhs, rhs in\n                let lp = groupPriority(lhs), rp = groupPriority(rhs)\n                if lp != rp { return lp < rp }\n                return lhs.name == rhs.name ? lhs.id < rhs.id : lhs.name < rhs.name\n            }',1)
if 'private func groupPriority(_ group: LeagueGroup)' not in s:
    marker='\n    var body: some View {'
    helper='''\n    private func groupPriority(_ group: LeagueGroup) -> Int {\n        let followed = group.items.contains { match in\n            match.homeID.map { favoriteTeams.contains($0) } == true || match.awayID.map { favoriteTeams.contains($0) } == true\n        }\n        let live = group.items.contains { store.isLive($0.status) }\n        return (followed ? 0 : 10) + (live ? 0 : 2)\n    }\n\n    private func leagueOption(for group: LeagueGroup) -> LeagueOption? {\n        LeagueOption.featured.first { $0.apiFootballID == group.id }\n    }\n'''
    s=s.replace(marker,helper+marker,1)
s=s.replace('                    SegmentBar(items: ["الكل", "مباشر", "القادمة", "المنتهية"], selected: $filter)','                    SegmentBar(items: ["الكل", "متابعاتي", "مباشر", "القادمة", "المنتهية"], selected: $filter)',1)
old='''                    ForEach(grouped) { group in\n                        leagueHeader(group)\n                        ForEach(group.items) { match in\n                            NavigationLink { V2MatchCenterView(match: match) } label: {\n                                APICompactMatchCard(match: match)\n                            }.buttonStyle(.plain)\n                        }\n                    }'''
new='''                    ForEach(grouped) { group in\n                        if let league = leagueOption(for: group) {\n                            NavigationLink { V2LeagueHubView(league: league) } label: { leagueHeader(group, showsChevron: true) }\n                                .buttonStyle(.plain)\n                                .accessibilityIdentifier("matches.league.\\(group.id)")\n                        } else {\n                            leagueHeader(group, showsChevron: false)\n                        }\n                        ForEach(group.items) { match in\n                            NavigationLink { V2MatchCenterView(match: match) } label: { APICompactMatchCard(match: match) }\n                                .buttonStyle(.plain)\n                                .accessibilityIdentifier("matches.match.\\(match.id)")\n                        }\n                    }'''
if old not in s: raise RuntimeError('matches grouped block marker missing')
s=s.replace(old,new,1)
s=s.replace('    private func leagueHeader(_ group: LeagueGroup) -> some View {\n','    private func leagueHeader(_ group: LeagueGroup, showsChevron: Bool) -> some View {\n',1)
s=s.replace('            Text("\\(group.items.count) مباراة").font(.caption).foregroundStyle(AppTheme.muted)\n','            Text("\\(group.items.count) مباراة").font(.caption).foregroundStyle(AppTheme.muted)\n            if showsChevron { Image(systemName: "chevron.left").font(.caption.bold()).foregroundStyle(AppTheme.muted) }\n',1)
write(path,s)

path='Sources/Views/APIProductionViews.swift'
s=read(path)
needle='''        .foregroundStyle(.white)\n        .padding(.horizontal, 15)'''
if needle not in s: raise RuntimeError('compact match card tap-target marker missing')
s=s.replace(needle,'''        .foregroundStyle(.white)\n        .contentShape(Rectangle())\n        .padding(.horizontal, 15)''',1)
write(path,s)

path='Sources/Views/V2Personalization.swift'
s=read(path)
marker='''        .padding(14)\n        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))'''
if marker in s:
    s=s.replace(marker,'''        .padding(14)\n        .contentShape(Rectangle())\n        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))''',1)
write(path,s)

path='UITests/ArabicJourneyTests.swift'
s=read(path)
if 'testMatchesHubInteractionPattern' not in s:
    marker='\n    @MainActor private func capture'
    test=r'''\n    @MainActor func testMatchesHubInteractionPattern() throws {\n        continueAfterFailure = false\n        let app = XCUIApplication()\n        app.launchArguments = ["-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]\n        app.launch()\n        XCTAssertTrue(app.tabBars.buttons["المباريات"].waitForExistence(timeout: 20))\n        app.tabBars.buttons["المباريات"].tap()\n        XCTAssertTrue(app.staticTexts["متابعاتي"].waitForExistence(timeout: 10))\n        let league = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "matches.league.")).firstMatch\n        if league.waitForExistence(timeout: 20) {\n            if !league.isHittable { app.swipeUp() }\n            league.tap()\n            XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 10))\n            app.navigationBars.buttons.firstMatch.tap()\n        }\n        let match = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "matches.match.")).firstMatch\n        if match.waitForExistence(timeout: 20) {\n            if !match.isHittable { app.swipeUp() }\n            match.tap()\n            XCTAssertTrue(app.staticTexts["نظرة عامة"].waitForExistence(timeout: 12))\n            XCTAssertTrue(app.staticTexts["الإحصائيات"].exists)\n            XCTAssertTrue(app.staticTexts["التشكيلة"].exists)\n        }\n    }\n'''
    if marker not in s: raise RuntimeError('UI test insertion marker missing')
    s=s.replace(marker,test+marker,1)
write(path,s)
print('popular football app UX fixes applied')
