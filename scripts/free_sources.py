"""Final integration of free-first loading, after the legacy release transforms."""
from pathlib import Path

def apply_free_sources(root):
    def edit(path, transform):
        file = root / path
        file.write_text(transform(file.read_text(encoding='utf-8')), encoding='utf-8')
    def replace(s, old, new):
        if new in s: return s
        if old not in s: raise RuntimeError('Free integration marker missing: ' + old[:100])
        return s.replace(old, new)
    def method(s, start, end, body):
        a = s.index(start); b = s.index(end, a)
        return s[:a] + body + '\n' + s[b:]
    def store(s):
        s = replace(s, 'struct APIPlusMatch: Identifiable, Hashable {', 'struct APIPlusMatch: Identifiable, Hashable, Codable {')
        s = replace(s, '    private var refreshedDay: String?', '    private var refreshedDay: String?\n    private var fixtureSnapshots: [String: FixtureSnapshot] = [:]\n    func fixtureSnapshot(for date: Date) -> FixtureSnapshot? { fixtureSnapshots[FreeFixtureFeed.key(date)] }')
        s = replace(s, 'today = matches; lastUpdated = Date(); refreshedDay = day; error = nil', 'today = matches; lastUpdated = fixtureSnapshot(for: Date())?.fetchedAt; refreshedDay = day; error = fixtureSnapshot(for: Date())?.warning')
        s = method(s, '    func fixtures(date:', '    func liveFixtures()', '''    func fixtures(date: Date, force: Bool = false) async throws -> [APIPlusMatch] {
        let snapshot = try await FreeFixtureFeed.shared.snapshot(date: date, force: force)
        try Task.checkCancellation()
        fixtureSnapshots[FreeFixtureFeed.key(date)] = snapshot
        return snapshot.matches
    }''')
        s = method(s, '    func searchTeams(', '    private func mapPlayer(', '''    func searchTeams(_ text: String) async throws -> [APIPlusTeam] {
        try await FreeSportsDirectory.teams(text)
    }
    func team(id: String) async throws -> APIPlusTeam? {
        try await FreeSportsDirectory.team(id)
    }
    func searchPlayers(_ text: String) async throws -> [APIPlusPlayer] {
        try await FreeSportsDirectory.players(text)
    }
    func player(id: String) async throws -> APIPlusPlayer? {
        try await FreeSportsDirectory.player(id)
    }
    func teamFixtures(teamID: String, teamName: String? = nil, next: Bool) async throws -> [APIPlusMatch] {
        if teamID.hasPrefix("espn:") { return try await PublicScoreboardSource.teamSchedule(id: teamID, next: next) }
        guard let name = teamName, let team = try await FreeSportsDirectory.teams(name).first else { throw FreeCoverageError.unavailable }
        return try await PublicScoreboardSource.teamSchedule(id: team.id, next: next)
    }''')
        s = method(s, '    func topScorers(', '    func playerSeasonStats(', '''    func topScorers(leagueID: String) async throws -> [APIPlusScorer] {
        throw FreeCoverageError.unavailable
    }''')
        s = method(s, '    func playerSeasonStats(', '    func searchTeams(', '''    func playerSeasonStats(playerID: String) async throws -> [APIPlusPlayerSeasonStat] {
        throw FreeCoverageError.unavailable
    }''')
        s = method(s, '    func leagueFixtures(', '    func standings(', '''    func leagueFixtures(leagueID: String, count: Int = 20) async throws -> [APIPlusMatch] {
        guard PublicScoreboardSource.leagues.contains(where: { $0.apiFootballID == leagueID }) else { throw FreeCoverageError.unavailable }
        async let past = PublicScoreboardSource.leagueWindow(leagueID: leagueID, next: false)
        async let future = PublicScoreboardSource.leagueWindow(leagueID: leagueID, next: true)
        let (a, b) = try await (past, future)
        var seen = Set<String>()
        return (a + b).filter { seen.insert($0.id).inserted }
    }''')
        return s
    edit('Sources/Core/APISportsStore.swift', store)
    def match(s):
        s = s.replace('if match.id.hasPrefix("np:") {', 'if match.id.hasPrefix("np:") || match.id.hasPrefix("espn:") {')
        s = replace(s, 'let detail = try await CanonicalSportsClient.detail(matchID: match.id, date: match.date)', 'let detail: CanonicalSportsClient.MatchDetail\n            if match.id.hasPrefix("espn:") { detail = try await FreeMatchDetail.load(match) }\n            else { detail = try await CanonicalSportsClient.detail(matchID: match.id, date: match.date) }')
        s = s.replace('            guard APIFootballClient.isConfigured else { throw APIFootballError.missingConfiguration }\n', '')
        s = replace(s, 'let result = try await store.fixtures(date: date)', 'let result = try await store.fixtures(date: date, force: force)')
        s = replace(s, 'resource.succeed(result, token: token)', 'resource.succeed(result, token: token, warning: store.fixtureSnapshot(for: date)?.warning, at: store.fixtureSnapshot(for: date)?.fetchedAt ?? Date())')
        s = replace(s, 'resource.succeed(store.today, token: token, at: updatedAt)', 'resource.succeed(store.today, token: token, warning: store.fixtureSnapshot(for: selectedDate)?.warning, at: updatedAt)')
        s = replace(s, 'TopBar(title: "المباريات", subtitle: "النتائج والمواعيد بتوقيت الرياض")', 'TopBar(title: "المباريات", subtitle: "المصدر: ESPN • البطولات المتاحة بتوقيت الرياض")')
        return s
    edit('Sources/Views/V2MatchExperience.swift', match)
    edit('Sources/Views/RootView.swift', lambda s: s.replace('guard network.isOnline, APIFootballClient.isConfigured else', 'guard network.isOnline else'))
    # Identity-only emergency records cannot override real public-provider IDs.
    edit('Sources/Views/V2Discovery.swift', lambda s: s.replace('SearchFallbackCatalog.mergeTeams(live, query: text)', 'live').replace('SearchFallbackCatalog.mergePlayers(live, query: text)', 'live').replace('let fallback = SearchFallbackCatalog.teams(query: text)', 'let fallback: [APIPlusTeam] = []').replace('let fallback = SearchFallbackCatalog.players(query: text)', 'let fallback: [APIPlusPlayer] = []'))
    edit('Sources/Views/PremiumGlobalSearch.swift', lambda s: s.replace('لاعب • نادي • بطولة • مباراة • خبر', 'الأندية: ESPN • اللاعبون: TheSportsDB • نتائج محدودة'))
    def more(s):
        s = s.replace('health?.ok == true && health?.providerConfigured != false && !healthError', '!healthError')
        s = s.replace('الخدمة متصلة وتعمل بشكل طبيعي', 'مصدر المباريات المجاني متصل')
        s = s.replace('حالة الخدمة', 'حالة المصادر المجانية')
        s = s.replace('health = try await APIFootballClient.health()', '_ = try await PublicScoreboardSource.fixtures(date: Date())')
        s = replace(s, '                    statusCard', '                    Text("المباريات والترتيب والأندية: ESPN. ملفات اللاعبين: TheSportsDB بنتائج بحث محدودة. الأخبار: RSS. التفاصيل المتقدمة غير متاحة ضمن هذه النسخة المجانية.")\n                        .font(.caption).foregroundStyle(AppTheme.muted).padding(.horizontal, 20)\n                    statusCard')
        return s
    edit('Sources/Views/V2Personalization.swift', more)
    edit('Sources/Views/V2Personalization.swift', lambda s: replace(s, '                    statusCard', '                    NavigationLink { FreeSourceSettingsView() } label: { card("مصادر البيانات", "الاتصال المباشر أو خادمك المجاني", "network") }\n                    statusCard'))
    for path in ['Sources/Core/PublicScoreboard.swift', 'Sources/Core/FreeSportsDirectory.swift', 'Sources/Core/FreeMatchDetail.swift', 'Sources/Views/PublicLeagueTableView.swift']:
        edit(path, lambda s: s.replace('URLSession.shared.data(for: request)', 'FreeSourceTransport.data(for: request)'))
    # Earlier release transforms append journeys using the former provider's IDs.
    edit('UITests/ArabicJourneyTests.swift', lambda s: s.replace('search.team.2938', 'search.team.espn:ksa.1:team:2276').replace('search.player.874', 'search.player.tsdb:34146304'))

if __name__ == '__main__': apply_free_sources(Path(__file__).resolve().parents[1])

