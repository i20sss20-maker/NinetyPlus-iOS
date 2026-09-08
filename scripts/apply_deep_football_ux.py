from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def write(path, text):
    (ROOT / path).write_text(text, encoding="utf-8")


# Home: add the fast, information-dense shortcuts users expect from leading score apps.
path = "Sources/Views/V2HomeView.swift"
s = read(path)
if "private var liveNow:" not in s:
    s = s.replace(
        '    private var leagues: Set<String> { Set(SavedFavoriteIDs.parse(favoriteLeagueIDs)) }\n',
        '    private var leagues: Set<String> { Set(SavedFavoriteIDs.parse(favoriteLeagueIDs)) }\n'
        '    private var liveNow: [APIPlusMatch] { today.filter { MatchLivePolicy.isLive($0.status) } }\n'
        '    private var followedToday: [APIPlusMatch] { today.filter { match in\n'
        '        match.homeID.map { teams.contains($0) } == true || match.awayID.map { teams.contains($0) } == true\n'
        '    } }\n',
        1,
    )
    s = s.replace(
        '                    header\n                    leagueSection\n',
        '                    header\n                    quickAccess\n                    leagueSection\n',
        1,
    )
    marker = '    private var leagueSection: some View {'
    quick = '''    private var quickAccess: some View {
        HStack(spacing: 10) {
            Button(action: openMatches) {
                quickCard(title: "مباشر الآن", value: String(liveNow.count), icon: "dot.radiowaves.left.and.right", active: !liveNow.isEmpty)
            }.accessibilityIdentifier("home.quick.live")
            Button(action: openMatches) {
                quickCard(title: "مبارياتك", value: String(followedToday.count), icon: "star.fill", active: !followedToday.isEmpty)
            }.accessibilityIdentifier("home.quick.following")
            NavigationLink { V2FavoritesView().toolbar(.visible, for: .navigationBar) } label: {
                quickCard(title: "متابعاتي", value: String(teams.count), icon: "person.2.fill", active: !teams.isEmpty)
            }.accessibilityIdentifier("home.quick.favorites")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }
    private func quickCard(title: String, value: String, icon: String, active: Bool) -> some View {
        VStack(spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.caption.bold())
                Text(value).font(.headline.bold()).monospacedDigit()
            }.foregroundStyle(active ? AppTheme.green : .white)
            Text(title).font(.caption2.bold()).foregroundStyle(AppTheme.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity).frame(minHeight: 72)
        .background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(active ? AppTheme.green.opacity(0.35) : AppTheme.border))
        .contentShape(Rectangle())
    }
'''
    if marker not in s:
        raise RuntimeError("home insertion marker missing")
    s = s.replace(marker, quick + marker, 1)
    # Home news should use the reliable in-app browser added in Build 96.
    s = s.replace('if let url = article.url { Link(destination: url) { DashboardNewsCard(article: article) }.buttonStyle(.plain) }',
                  'if let url = article.url { InAppWebLink(url: url) { DashboardNewsCard(article: article) }.buttonStyle(.plain) }')
write(path, s)


# Team page: surface next match + latest result immediately, before long fixture lists.
path = "Sources/Views/V2Discovery.swift"
s = read(path)
if "private var nextMatch:" not in s:
    s = s.replace(
        '    private var followed: Bool { SavedFavoriteIDs.parse(favoriteTeamIDs).contains(team.id) }\n',
        '    private var followed: Bool { SavedFavoriteIDs.parse(favoriteTeamIDs).contains(team.id) }\n'
        '    private var nextMatch: APIPlusMatch? { (upcoming.value ?? []).sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }.first }\n'
        '    private var latestMatch: APIPlusMatch? { (recent.value ?? []).sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }.first }\n',
        1,
    )
    s = s.replace(
        '                }.padding(20).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 24)).padding(.horizontal, 16)\n                matchSection("الأيام السبعة القادمة", state: upcoming)\n',
        '                }.padding(20).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 24)).padding(.horizontal, 16)\n                teamSnapshot\n                matchSection("الأيام السبعة القادمة", state: upcoming)\n',
        1,
    )
    marker = '    private func matchSection(_ title: String, state: PageResource<[APIPlusMatch]>) -> some View {'
    block = '''    private var teamSnapshot: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ملخص النادي").font(.headline).padding(.horizontal, 20)
            HStack(spacing: 10) {
                snapshotCard("المباراة القادمة", match: nextMatch, icon: "calendar")
                snapshotCard("آخر نتيجة", match: latestMatch, icon: "clock.arrow.circlepath")
            }.padding(.horizontal, 16)
        }.accessibilityIdentifier("team.snapshot")
    }
    @ViewBuilder private func snapshotCard(_ title: String, match: APIPlusMatch?, icon: String) -> some View {
        if let match {
            NavigationLink { V2MatchCenterView(match: match) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Label(title, systemImage: icon).font(.caption.bold()).foregroundStyle(AppTheme.green)
                    Text("\(SportsArabic.team(match.home)) × \(SportsArabic.team(match.away))")
                        .font(.caption.weight(.semibold)).foregroundStyle(.white).lineLimit(2)
                    if let date = match.date { Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(AppTheme.muted) }
                    else { Text(MatchLivePolicy.statusText(match.status, elapsed: match.elapsed)).font(.caption2).foregroundStyle(AppTheme.muted) }
                }.frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
                    .padding(13).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppTheme.border))
            }.buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon).font(.caption.bold()).foregroundStyle(AppTheme.muted)
                Text("لا توجد بيانات منشورة").font(.caption).foregroundStyle(AppTheme.muted)
            }.frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
                .padding(13).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppTheme.border))
        }
    }
'''
    if marker not in s:
        raise RuntimeError("team insertion marker missing")
    s = s.replace(marker, block + marker, 1)
    s = s.replace(
        'NavigationLink { V2MatchCenterView(match: match) } label: { APICompactMatchCard(match: match) }.buttonStyle(.plain)',
        'NavigationLink { V2MatchCenterView(match: match) } label: { APICompactMatchCard(match: match) }.buttonStyle(.plain).accessibilityIdentifier("team.match.\\(match.id)")',
        1,
    )

# Player page: put the season headline numbers before the detailed competition cards.
if "private var totalAppearances:" not in s:
    s = s.replace(
        '    private var isPreviousSeason: Bool { resource.value?.first.map { $0.season != APIFootballClient.currentSeason } ?? false }\n',
        '    private var isPreviousSeason: Bool { resource.value?.first.map { $0.season != APIFootballClient.currentSeason } ?? false }\n'
        '    private var totalAppearances: Int { (resource.value ?? []).reduce(0) { $0 + ($1.appearances ?? 0) } }\n'
        '    private var totalGoals: Int { (resource.value ?? []).reduce(0) { $0 + ($1.goals ?? 0) } }\n'
        '    private var totalAssists: Int { (resource.value ?? []).reduce(0) { $0 + ($1.assists ?? 0) } }\n'
        '    private var totalMinutes: Int { (resource.value ?? []).reduce(0) { $0 + ($1.minutes ?? 0) } }\n',
        1,
    )
    s = s.replace(
        '                }.frame(maxWidth: .infinity, alignment: .leading)\n                PageLoadFeedback(loading: resource.isLoading || resource.key == nil, hasValue: resource.value != nil, message: resource.errorMessage, updatedAt: nil) { retry += 1 }\n',
        '                }.frame(maxWidth: .infinity, alignment: .leading)\n                seasonSummary\n                PageLoadFeedback(loading: resource.isLoading || resource.key == nil, hasValue: resource.value != nil, message: resource.errorMessage, updatedAt: nil) { retry += 1 }\n',
        1,
    )
    marker = '    private func metric(_ title: String, _ value: Int?) -> some View {'
    block = '''    private var seasonSummary: some View {
        HStack(spacing: 0) {
            metric("مباريات", totalAppearances)
            Divider().frame(height: 38).overlay(AppTheme.border)
            metric("أهداف", totalGoals)
            Divider().frame(height: 38).overlay(AppTheme.border)
            metric("صناعة", totalAssists)
            Divider().frame(height: 38).overlay(AppTheme.border)
            metric("دقائق", totalMinutes)
        }
        .padding(.vertical, 14)
        .background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(AppTheme.border))
        .accessibilityIdentifier("player.summary")
    }
'''
    if marker not in s:
        raise RuntimeError("player insertion marker missing")
    s = s.replace(marker, block + marker, 1)
    s = s.replace('                    }.accessibilityIdentifier("team.follow")', '                    }.accessibilityIdentifier("team.follow")', 1)
    s = s.replace(
        '                    Button(action: toggleFollow) {\n                        Label(followed ? "متابَع" : "متابعة اللاعب"',
        '                    Button(action: toggleFollow) {\n                        Label(followed ? "متابَع" : "متابعة اللاعب"',
        1,
    )
    # Attach a stable identifier to player follow without changing its appearance.
    player_button = '                    }\n                }.frame(maxWidth: .infinity).padding(20).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 24))'
    if player_button in s:
        s = s.replace(player_button, '                    }.accessibilityIdentifier("player.follow")\n                }.frame(maxWidth: .infinity).padding(20).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 24))', 1)
write(path, s)


# Match center: team crests/names become direct club destinations, like leading score apps.
path = "Sources/Views/V2MatchExperience.swift"
s = read(path)
if 'identifier: "match.team.home"' not in s:
    s = s.replace('                    team(m.home, m.homeLogo)\n', '                    team(m.home, m.homeLogo, id: m.homeID, identifier: "match.team.home")\n', 1)
    s = s.replace('                    team(m.away, m.awayLogo)\n', '                    team(m.away, m.awayLogo, id: m.awayID, identifier: "match.team.away")\n', 1)
    old = '''    private func team(_ name: String, _ logo: String?) -> some View {
        VStack(spacing: 8) {
            RemoteBadge(url: logo).frame(width: 72, height: 72)
            Text(SportsArabic.team(name))
                .font(.subheadline.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .frame(width: 108)
        }
    }
'''
    new = '''    @ViewBuilder private func team(_ name: String, _ logo: String?, id: String?, identifier: String) -> some View {
        if let id {
            NavigationLink { V2TeamLookupView(teamID: id, fallbackName: name, logo: logo) } label: {
                teamIdentity(name, logo)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(identifier)
        } else {
            teamIdentity(name, logo).accessibilityIdentifier(identifier)
        }
    }
    private func teamIdentity(_ name: String, _ logo: String?) -> some View {
        VStack(spacing: 8) {
            RemoteBadge(url: logo).frame(width: 72, height: 72)
            Text(SportsArabic.team(name))
                .font(.subheadline.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .frame(width: 108)
            Text("صفحة النادي").font(.caption2).foregroundStyle(AppTheme.green)
        }
        .contentShape(Rectangle())
    }
'''
    if old not in s:
        raise RuntimeError("match team helper marker missing")
    s = s.replace(old, new, 1)
    # Make the follow control addressable in device QA.
    s = s.replace('                }.buttonStyle(.plain).disabled(followBusy)\n', '                }.buttonStyle(.plain).disabled(followBusy).accessibilityIdentifier("match.follow")\n', 1)
write(path, s)


# Expand device QA around the new information architecture.
path = "UITests/ArabicJourneyTests.swift"
s = read(path)
if "testDeepFootballNavigationAndSummaries" not in s:
    marker = "\n    @MainActor private func capture"
    test = r'''
    @MainActor func testDeepFootballNavigationAndSummaries() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        app.launch()
        XCTAssertTrue(app.buttons["home.quick.live"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["home.quick.following"].exists)
        XCTAssertTrue(app.buttons["home.quick.favorites"].exists)

        app.buttons["home.search"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10))
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("الاتحاد\n")
        let club = app.buttons["search.team.2938"]
        XCTAssertTrue(club.waitForExistence(timeout: 35))
        club.tap()
        XCTAssertTrue(app.buttons["team.follow"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "team.snapshot").firstMatch.waitForExistence(timeout: 25))
        app.navigationBars.buttons.firstMatch.tap()

        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10))
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.clearAndType("رونالدو\n")
        let player = app.buttons["search.player.874"]
        XCTAssertTrue(player.waitForExistence(timeout: 35))
        if !player.isHittable { app.swipeUp() }
        player.tap()
        XCTAssertTrue(app.staticTexts["player.name"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "player.summary").firstMatch.waitForExistence(timeout: 30))
    }
'''
    # XCTest has no built-in clearAndType; keep the test portable with select-all deletion helper below.
    test = test.replace('app.searchFields.firstMatch.clearAndType("رونالدو\\n")', 'app.searchFields.firstMatch.press(forDuration: 1.0); app.keys["Select All"].tap(); app.keys[XCUIKeyboardKey.delete.rawValue].tap(); app.searchFields.firstMatch.typeText("رونالدو\\n")')
    if marker not in s:
        raise RuntimeError("UI test insertion marker missing")
    s = s.replace(marker, test + marker, 1)
write(path, s)

print("deep football UX fixes applied")
