"""Build 100 product-polish pass layered after all earlier release transforms."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def read(path): return (ROOT / path).read_text(encoding="utf-8")
def write(path, text): (ROOT / path).write_text(text, encoding="utf-8")

def replace_once(text, old, new, label):
    if new in text:
        return text
    if old not in text:
        raise RuntimeError(f"Build 100 marker missing: {label}")
    return text.replace(old, new, 1)

# Home: put what matters now before catalogue-style league browsing.
path = "Sources/Views/V2HomeView.swift"
s = read(path)
old = '''                    header
                    quickAccess
                    leagueSection
                    if let match = today.first {
                        NavigationLink { V2MatchCenterView(match: match).toolbar(.visible, for: .navigationBar) } label: { DashboardMatchHero(match: match) }
                            .buttonStyle(.plain).accessibilityIdentifier("home.featuredMatch")
                    }
                    todaySection
                    personalSection
                    newsSection'''
new = '''                    header
                    quickAccess
                    if let match = today.first {
                        NavigationLink { V2MatchCenterView(match: match).toolbar(.visible, for: .navigationBar) } label: { DashboardMatchHero(match: match) }
                            .buttonStyle(.plain).accessibilityIdentifier("home.featuredMatch")
                    }
                    personalSection
                    todaySection
                    leagueSection
                    newsSection'''
s = replace_once(s, old, new, "home information hierarchy")
write(path, s)

# League hub: follow from the league itself and preserve loaded section content on retries.
path = "Sources/Views/V2LeagueHub.swift"
s = read(path)
if '@AppStorage("ninetyplus.favoriteLeagueIDs")' not in s:
    s = s.replace('    @State private var publicRefresh = 0\n', '    @State private var publicRefresh = 0\n    @AppStorage("ninetyplus.favoriteLeagueIDs") private var favoriteLeagueIDs = ""\n', 1)
if 'private var followedLeague:' not in s:
    s = s.replace('    private var scorerSeasonIsFallback: Bool { scorers.first.map { $0.season != APIFootballClient.currentSeason } ?? false }\n', '    private var scorerSeasonIsFallback: Bool { scorers.first.map { $0.season != APIFootballClient.currentSeason } ?? false }\n    private var followedLeague: Bool { SavedFavoriteIDs.parse(favoriteLeagueIDs).contains(league.apiFootballID) }\n', 1)
old_header = '''            VStack(alignment: .leading, spacing: 7) {
                Text(league.arabicName).font(.title2.bold()).foregroundStyle(.white).accessibilityIdentifier("league.hub.\\(league.apiFootballID)")
                Text("الترتيب والنتائج وأندية البطولة").font(.caption).foregroundStyle(AppTheme.muted)
            }
            Spacer(minLength: 0)'''
new_header = '''            VStack(alignment: .leading, spacing: 7) {
                Text(league.arabicName).font(.title2.bold()).foregroundStyle(.white).accessibilityIdentifier("league.hub.\\(league.apiFootballID)")
                Text("الترتيب والنتائج وأندية البطولة").font(.caption).foregroundStyle(AppTheme.muted)
                Button(action: toggleLeagueFollow) {
                    Label(followedLeague ? "متابَعة" : "متابعة البطولة", systemImage: followedLeague ? "star.fill" : "star")
                        .font(.caption.bold()).foregroundStyle(followedLeague ? .black : AppTheme.green)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(followedLeague ? AppTheme.green : AppTheme.green.opacity(0.10), in: Capsule())
                }.buttonStyle(.plain).accessibilityIdentifier("league.follow")
            }
            Spacer(minLength: 0)'''
s = replace_once(s, old_header, new_header, "league follow control")
s = s.replace('let token = matchesState.begin(key: key)', 'let token = matchesState.begin(key: key, retainingValue: true)', 1)
s = s.replace('let token = scorersState.begin(key: key)', 'let token = scorersState.begin(key: key, retainingValue: true)', 1)
if 'private func toggleLeagueFollow()' not in s:
    marker = '    @MainActor private func load(force: Bool = false) async {'
    helper = '''    private func toggleLeagueFollow() {
        var ids = Set(SavedFavoriteIDs.parse(favoriteLeagueIDs))
        if followedLeague { ids.remove(league.apiFootballID) } else { ids.insert(league.apiFootballID) }
        favoriteLeagueIDs = ids.sorted().joined(separator: ",")
    }

'''
    if marker not in s: raise RuntimeError("Build 100 marker missing: league toggle insertion")
    s = s.replace(marker, helper + marker, 1)

# Team/player lookup should open a useful shell even when provider detail lookup fails.
team_decl = '''struct V2TeamLookupView: View {
    let teamID: String
    let fallbackName: String
    let logo: String?
    @State private var resource = PageResource<APIPlusTeam?>()'''
team_new = '''struct V2TeamLookupView: View {
    let teamID: String
    let fallbackName: String
    let logo: String?
    @State private var resource = PageResource<APIPlusTeam?>()
    private var fallbackTeam: APIPlusTeam {
        APIPlusTeam(id: teamID, name: fallbackName, country: nil, founded: nil, logo: logo, venue: nil, city: nil, venueImage: nil)
    }'''
s = replace_once(s, team_decl, team_new, "team fallback model")
team_group = '''        Group {
            if resource.key == teamID, let team = resource.value ?? nil { V2TeamView(team: team) }
            else {
                ScrollView {'''
team_group_new = '''        Group {
            if resource.key == teamID, let team = resource.value ?? nil { V2TeamView(team: team) }
            else if resource.key == teamID, resource.errorMessage != nil { V2TeamView(team: fallbackTeam) }
            else {
                ScrollView {'''
s = replace_once(s, team_group, team_group_new, "team fallback destination")

player_decl = '''struct V2PlayerLookupView: View {
    let playerID: String
    let fallbackName: String
    let photo: String?
    @State private var resource = PageResource<APIPlusPlayer?>()'''
player_new = '''struct V2PlayerLookupView: View {
    let playerID: String
    let fallbackName: String
    let photo: String?
    @State private var resource = PageResource<APIPlusPlayer?>()
    private var fallbackPlayer: APIPlusPlayer {
        APIPlusPlayer(id: playerID, name: fallbackName, nationality: nil, birth: nil, height: nil, weight: nil, photo: photo)
    }'''
s = replace_once(s, player_decl, player_new, "player fallback model")
player_group = '''        Group {
            if resource.key == playerID, let player = resource.value ?? nil { V2PlayerView(player: player) }
            else {
                ScrollView {'''
player_group_new = '''        Group {
            if resource.key == playerID, let player = resource.value ?? nil { V2PlayerView(player: player) }
            else if resource.key == playerID, resource.errorMessage != nil { V2PlayerView(player: fallbackPlayer) }
            else {
                ScrollView {'''
s = replace_once(s, player_group, player_group_new, "player fallback destination")
write(path, s)

# Club/player pages: retain prior values during refresh instead of flashing to empty.
path = "Sources/Views/V2Discovery.swift"
s = read(path)
s = s.replace('let token = next ? upcoming.begin(key: team.id) : recent.begin(key: team.id)', 'let token = next ? upcoming.begin(key: team.id, retainingValue: true) : recent.begin(key: team.id, retainingValue: true)', 1)
s = s.replace('let token = resource.begin(key: player.id)', 'let token = resource.begin(key: player.id, retainingValue: true)', 1)
write(path, s)

print("Build 100 product polish applied")

# Later product passes are chained here because all release workflows already run
# this final product-polish step after canonical + resilience transformations.
for patch_name in ("apply_build102_windowed_fixtures.py", "apply_build103_team_window_coalescing.py"):
    next_patch = ROOT / "scripts" / patch_name
    if next_patch.exists():
        exec(compile(next_patch.read_text(encoding="utf-8"), str(next_patch), "exec"), {"__name__": "__main__"})
