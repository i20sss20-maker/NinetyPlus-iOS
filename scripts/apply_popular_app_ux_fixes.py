from pathlib import Path
import runpy

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
    helper='''
    private func groupPriority(_ group: LeagueGroup) -> Int {
        let followed = group.items.contains { match in
            match.homeID.map { favoriteTeams.contains($0) } == true || match.awayID.map { favoriteTeams.contains($0) } == true
        }
        let live = group.items.contains { store.isLive($0.status) }
        return (followed ? 0 : 10) + (live ? 0 : 2)
    }

    private func leagueOption(for group: LeagueGroup) -> LeagueOption? {
        LeagueOption.featured.first { $0.apiFootballID == group.id }
    }
'''
    s=s.replace(marker,helper+marker,1)
s=s.replace('                    SegmentBar(items: ["الكل", "مباشر", "القادمة", "المنتهية"], selected: $filter)','                    SegmentBar(items: ["الكل", "متابعاتي", "مباشر", "القادمة", "المنتهية"], selected: $filter)',1)
old='''                    ForEach(grouped) { group in
                        leagueHeader(group)
                        ForEach(group.items) { match in
                            NavigationLink { V2MatchCenterView(match: match) } label: {
                                APICompactMatchCard(match: match)
                            }.buttonStyle(.plain)
                        }
                    }'''
new=r'''                    ForEach(grouped) { group in
                        if let league = leagueOption(for: group) {
                            NavigationLink { V2LeagueHubView(league: league) } label: { leagueHeader(group, showsChevron: true) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("matches.league.\(group.id)")
                        } else {
                            leagueHeader(group, showsChevron: false)
                        }
                        ForEach(group.items) { match in
                            NavigationLink { V2MatchCenterView(match: match) } label: { APICompactMatchCard(match: match) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("matches.match.\(match.id)")
                        }
                    }'''
if old not in s: raise RuntimeError('matches grouped block marker missing')
s=s.replace(old,new,1)
s=s.replace('    private func leagueHeader(_ group: LeagueGroup) -> some View {\n','    private func leagueHeader(_ group: LeagueGroup, showsChevron: Bool) -> some View {\n',1)
s=s.replace('            Text("\\(group.items.count) مباراة").font(.caption).foregroundStyle(AppTheme.muted)\n','            Text("\\(group.items.count) مباراة").font(.caption).foregroundStyle(AppTheme.muted)\n            if showsChevron { Image(systemName: "chevron.left").font(.caption.bold()).foregroundStyle(AppTheme.muted) }\n',1)
write(path,s)

path='Sources/Views/APIProductionViews.swift'
s=read(path)
needle='''        .foregroundStyle(.white)
        .padding(.horizontal, 15)'''
if needle not in s: raise RuntimeError('compact match card tap-target marker missing')
s=s.replace(needle,'''        .foregroundStyle(.white)
        .contentShape(Rectangle())
        .padding(.horizontal, 15)''',1)
write(path,s)

path='Sources/Views/V2Personalization.swift'
s=read(path)
marker='''        .padding(14)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))'''
if marker in s:
    s=s.replace(marker,'''        .padding(14)
        .contentShape(Rectangle())
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))''',1)
write(path,s)

# Add the matches-hub interaction test. SegmentBar items are SwiftUI Buttons, not static text.
path='UITests/ArabicJourneyTests.swift'
s=read(path)
if 'testMatchesHubInteractionPattern' not in s:
    marker='\n    @MainActor private func capture'
    test='''

    @MainActor func testMatchesHubInteractionPattern() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["المباريات"].waitForExistence(timeout: 20))
        app.tabBars.buttons["المباريات"].tap()
        XCTAssertTrue(app.buttons["متابعاتي"].waitForExistence(timeout: 10))
        let league = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "matches.league.")).firstMatch
        if league.waitForExistence(timeout: 20) {
            if !league.isHittable { app.swipeUp() }
            league.tap()
            XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 10))
            app.navigationBars.buttons.firstMatch.tap()
        }
        let match = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "matches.match.")).firstMatch
        if match.waitForExistence(timeout: 20) {
            if !match.isHittable { app.swipeUp() }
            match.tap()
            XCTAssertTrue(app.buttons["match.follow"].waitForExistence(timeout: 12))
            XCTAssertTrue(app.staticTexts["نظرة عامة"].exists || app.buttons["نظرة عامة"].exists)
            XCTAssertTrue(app.staticTexts["الإحصائيات"].exists || app.buttons["الإحصائيات"].exists)
            XCTAssertTrue(app.staticTexts["التشكيلة"].exists || app.buttons["التشكيلة"].exists)
        }
    }
'''
    if marker not in s: raise RuntimeError('UI test insertion marker missing')
    s=s.replace(marker,test+marker,1)
write(path,s)

# Build 98 deeper UX patch adds home/club/player/match-center features and its test.
runpy.run_path(str(ROOT / 'scripts/apply_deep_football_ux.py'), run_name='__main__')

# Make the deep test independent of localized keyboard editing. Relaunch before the
# player search instead of attempting an English "Select All" command on Arabic iOS.
path='UITests/ArabicJourneyTests.swift'
s=read(path)
old='''        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10))
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.press(forDuration: 1.0); app.keys["Select All"].tap(); app.keys[XCUIKeyboardKey.delete.rawValue].tap(); app.searchFields.firstMatch.typeText("رونالدو\\n")
        let player = app.buttons["search.player.874"]'''
new='''        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["البحث"].waitForExistence(timeout: 20))
        app.tabBars.buttons["البحث"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10))
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("رونالدو\\n")
        let player = app.buttons["search.player.874"]'''
if old not in s:
    raise RuntimeError('deep player-search QA cleanup marker missing')
s=s.replace(old,new,1)
write(path,s)

print('popular football app UX fixes applied')
