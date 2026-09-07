"""Deterministic source transformations shared by distributable and visual QA builds.
They keep Arabic presentation Gregorian, preserve metric units, and activate the
keyless public fixture fallback when the primary provider is unavailable.
"""
from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f"release patch pattern missing: {label}")
    return text.replace(old, new, 1)

# Gregorian sports dates and public-fallback match-center safety.
match = Path("Sources/Views/V2MatchExperience.swift")
s = match.read_text()
replacements = {
    '@State private var selectedDate = Calendar.current.startOfDay(for: Date())': '@State private var selectedDate = SportsDisplayDate.calendar.startOfDay(for: Date())',
    '@State private var dayAnchor = Calendar.current.startOfDay(for: Date())': '@State private var dayAnchor = SportsDisplayDate.calendar.startOfDay(for: Date())',
    'private var selectedDay: Date { Calendar.current.startOfDay(for: selectedDate) }': 'private var selectedDay: Date { SportsDisplayDate.calendar.startOfDay(for: selectedDate) }',
    'private var days: [Date] { (-3...3).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: dayAnchor) } }': 'private var days: [Date] { (-3...3).compactMap { SportsDisplayDate.calendar.date(byAdding: .day, value: $0, to: dayAnchor) } }',
    'guard let updatedAt, Calendar.current.isDateInToday(selectedDate),': 'guard let updatedAt, SportsDisplayDate.calendar.isDateInToday(selectedDate),',
    'let selected = Calendar.current.isDate(day, inSameDayAs: selectedDate)': 'let selected = SportsDisplayDate.calendar.isDate(day, inSameDayAs: selectedDate)',
    'Text(day.formatted(.dateTime.day())).font(.headline.bold())': 'Text(SportsDisplayDate.label(day, pattern: "d")).font(.headline.bold())',
    'Text(day.formatted(.dateTime.month(.abbreviated))).font(.caption2)': 'Text(SportsDisplayDate.label(day, pattern: "MMM")).font(.caption2)',
    'if Calendar.current.isDateInToday(day) { return "اليوم" }': 'if SportsDisplayDate.calendar.isDateInToday(day) { return "اليوم" }',
    'if Calendar.current.isDateInYesterday(day) { return "أمس" }': 'if SportsDisplayDate.calendar.isDateInYesterday(day) { return "أمس" }',
    'if Calendar.current.isDateInTomorrow(day) { return "غدًا" }': 'if SportsDisplayDate.calendar.isDateInTomorrow(day) { return "غدًا" }',
    'let formatter = DateFormatter()\n        formatter.locale = Locale(identifier: "ar_SA")\n        formatter.dateFormat = "EEE"\n        return formatter.string(from: day)': 'return SportsDisplayDate.label(day, pattern: "EEE")',
    'Text(date.formatted(date: .abbreviated, time: .shortened))': 'Text(SportsDisplayDate.label(date, pattern: "d MMMM yyyy، HH:mm"))',
    'Text(date, style: .time)': 'Text(SportsDisplayDate.label(date, pattern: "HH:mm"))',
    'infoRow("الموعد", date.formatted(date: .abbreviated, time: .shortened))': 'infoRow("الموعد", SportsDisplayDate.label(date, pattern: "d MMMM yyyy، HH:mm"))',
}
for old, new in replacements.items():
    s = s.replace(old, new)

fallback_guard_old = '''        prepare(match)\n        let displayed = current ?? match\n        if section == .h2h {'''
fallback_guard_new = '''        prepare(match)\n        if PublicScoreboardSource.isFallbackID(match.id) {\n            progress.markUnavailable(section)\n            return\n        }\n        let displayed = current ?? match\n        if section == .h2h {'''
s = replace_once(s, fallback_guard_old, fallback_guard_new, "public match-center guard")
match.write_text(s)

# Player measurements retain explicit Arabic units.
player = Path("Sources/Views/V2Discovery.swift")
s = player.read_text()
s = s.replace('info("الطول", player.height?.replacingOccurrences(of: "cm", with: "سم"))', 'info("الطول", measurement(player.height, unit: "سم"))')
s = s.replace('info("الوزن", player.weight?.replacingOccurrences(of: "kg", with: "كجم"))', 'info("الوزن", measurement(player.weight, unit: "كجم"))')
needle = '    private func metric(_ title: String, _ value: Int?) -> some View {'
helper = '''    private func measurement(_ raw: String?, unit: String) -> String? {\n        guard let raw else { return nil }\n        let digits = raw.filter { $0.isNumber || $0 == "." }\n        guard !digits.isEmpty else { return nil }\n        return "\\(digits) \\(unit)"\n    }\n'''
if helper not in s:
    if needle not in s:
        raise SystemExit("release patch pattern missing: player measurement helper")
    s = s.replace(needle, helper + needle, 1)
# Club detail can use the public scoreboard by name if the primary fixture window is unavailable.
s = s.replace('APISportsStore.shared.teamFixtures(teamID: team.id, next: next)', 'APISportsStore.shared.teamFixtures(teamID: team.id, teamName: team.name, next: next)')
player.write_text(s)

# API-Football stays primary. Public scoreboard is a no-key continuity layer for
# the home/matches/league pages when the free-plan budget is exhausted.
store = Path("Sources/Core/APISportsStore.swift")
s = store.read_text()
fixtures_old = '''    func fixtures(date: Date, force: Bool = false) async throws -> [APIPlusMatch] {\n        let fixtures = try await SharedFixtureDays.shared.fetch(date, force: force)\n        try Task.checkCancellation()\n        return fixtures.map(mapMatch).sorted { a, b in\n            let pa = priority(a), pb = priority(b)\n            if pa != pb { return pa > pb }\n            if a.date != b.date { return (a.date ?? .distantFuture) < (b.date ?? .distantFuture) }\n            return a.id < b.id\n        }\n    }'''
fixtures_new = '''    func fixtures(date: Date, force: Bool = false) async throws -> [APIPlusMatch] {\n        do {\n            let fixtures = try await SharedFixtureDays.shared.fetch(date, force: force)\n            try Task.checkCancellation()\n            return fixtures.map(mapMatch).sorted { a, b in\n                let pa = priority(a), pb = priority(b)\n                if pa != pb { return pa > pb }\n                if a.date != b.date { return (a.date ?? .distantFuture) < (b.date ?? .distantFuture) }\n                return a.id < b.id\n            }\n        } catch {\n            if error is CancellationError { throw error }\n            let fallback = try await PublicScoreboardSource.fixtures(date: date, force: force)\n            try Task.checkCancellation()\n            return fallback.sorted { a, b in\n                let pa = priority(a), pb = priority(b)\n                if pa != pb { return pa > pb }\n                if a.date != b.date { return (a.date ?? .distantFuture) < (b.date ?? .distantFuture) }\n                return a.id < b.id\n            }\n        }\n    }'''
s = replace_once(s, fixtures_old, fixtures_new, "fixtures fallback")

league_old = '''    func leagueFixtures(leagueID: String, count: Int = 20) async throws -> [APIPlusMatch] {\n        async let recent = SharedFixtureDays.shared.window(next: false)\n        async let upcoming = SharedFixtureDays.shared.window(next: true)\n        let (past, future) = try await (recent, upcoming)\n        var seen = Set<String>()\n        let matches = (past + future).filter { $0.league.id.map(String.init) == leagueID }.map(mapMatch)\n        return matches.filter { seen.insert($0.id).inserted }.sorted { a, b in\n            let phaseA = FixturePhase.isFinished(a.status) ? 1 : 0\n            let phaseB = FixturePhase.isFinished(b.status) ? 1 : 0\n            if phaseA != phaseB { return phaseA < phaseB }\n            return phaseA == 0 ? (a.date ?? .distantFuture) < (b.date ?? .distantFuture) : (a.date ?? .distantPast) > (b.date ?? .distantPast)\n        }\n    }'''
league_new = '''    func leagueFixtures(leagueID: String, count: Int = 20) async throws -> [APIPlusMatch] {\n        var output: [APIPlusMatch]\n        do {\n            async let recent = SharedFixtureDays.shared.window(next: false)\n            async let upcoming = SharedFixtureDays.shared.window(next: true)\n            let (past, future) = try await (recent, upcoming)\n            output = (past + future).filter { $0.league.id.map(String.init) == leagueID }.map(mapMatch)\n        } catch {\n            if error is CancellationError { throw error }\n            async let recent = PublicScoreboardSource.leagueWindow(leagueID: leagueID, next: false)\n            async let upcoming = PublicScoreboardSource.leagueWindow(leagueID: leagueID, next: true)\n            let (past, future) = try await (recent, upcoming)\n            output = past + future\n        }\n        var seen = Set<String>()\n        return output.filter { seen.insert($0.id).inserted }.sorted { a, b in\n            let phaseA = FixturePhase.isFinished(a.status) ? 1 : 0\n            let phaseB = FixturePhase.isFinished(b.status) ? 1 : 0\n            if phaseA != phaseB { return phaseA < phaseB }\n            return phaseA == 0 ? (a.date ?? .distantFuture) < (b.date ?? .distantFuture) : (a.date ?? .distantPast) > (b.date ?? .distantPast)\n        }\n    }'''
s = replace_once(s, league_old, league_new, "league fixtures fallback")

team_old = '''    func teamFixtures(teamID: String, next: Bool) async throws -> [APIPlusMatch] {\n        let fixtures = try await SharedFixtureDays.shared.window(next: next)\n        try Task.checkCancellation()\n        return fixtures.filter { item in\n            (item.teams.home.id.map(String.init) == teamID || item.teams.away.id.map(String.init) == teamID)\n        }.map(mapMatch).filter { match in\n            next ? (FixturePhase.isUpcoming(match.status) || isLive(match.status)) : FixturePhase.isFinished(match.status)\n        }.sorted { a, b in\n            next ? (a.date ?? .distantFuture) < (b.date ?? .distantFuture) : (a.date ?? .distantPast) > (b.date ?? .distantPast)\n        }\n    }'''
team_new = '''    func teamFixtures(teamID: String, teamName: String? = nil, next: Bool) async throws -> [APIPlusMatch] {\n        do {\n            let fixtures = try await SharedFixtureDays.shared.window(next: next)\n            try Task.checkCancellation()\n            return fixtures.filter { item in\n                (item.teams.home.id.map(String.init) == teamID || item.teams.away.id.map(String.init) == teamID)\n            }.map(mapMatch).filter { match in\n                next ? (FixturePhase.isUpcoming(match.status) || isLive(match.status)) : FixturePhase.isFinished(match.status)\n            }.sorted { a, b in\n                next ? (a.date ?? .distantFuture) < (b.date ?? .distantFuture) : (a.date ?? .distantPast) > (b.date ?? .distantPast)\n            }\n        } catch {\n            if error is CancellationError { throw error }\n            guard let teamName, !teamName.isEmpty else { throw error }\n            let matches = try await PublicScoreboardSource.teamWindow(teamName: teamName, next: next)\n            return matches.filter { match in\n                next ? (FixturePhase.isUpcoming(match.status) || isLive(match.status)) : FixturePhase.isFinished(match.status)\n            }.sorted { a, b in\n                next ? (a.date ?? .distantFuture) < (b.date ?? .distantFuture) : (a.date ?? .distantPast) > (b.date ?? .distantPast)\n            }\n        }\n    }'''
s = replace_once(s, team_old, team_new, "team fixtures fallback")
store.write_text(s)

# Keep nested fallback cache references explicit for Swift compiler versions.
public = Path("Sources/Core/PublicScoreboard.swift")
s = public.read_text()
s = s.replace('let key = "\\(league.espnCode):\\(dayKey(date))"', 'let key = "\\(league.espnCode):\\(PublicScoreboardSource.dayKey(date))"')
s = s.replace('let task = Task { try await fetchRemote(date: date, league: league) }', 'let task = Task { try await PublicScoreboardSource.fetchRemote(date: date, league: league) }')
public.write_text(s)

print("Applied release UI and public-scoreboard fallback fixes")
