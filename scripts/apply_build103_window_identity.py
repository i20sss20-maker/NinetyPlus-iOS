"""Build 103: pass the club name through canonical window requests.

ESPN and API-Football use different team IDs. The name is therefore part of the
fallback identity only; the provider query itself remains keyed by the API team ID.
"""
from pathlib import Path

client = Path("Sources/Core/CanonicalSportsClient.swift")
s = client.read_text(encoding="utf-8")
old = 'static func window(from: Date, to: Date, teamID: String? = nil, leagueID: String? = nil, season: Int? = nil) async throws -> WindowResponse {'
new = 'static func window(from: Date, to: Date, teamID: String? = nil, teamName: String? = nil, leagueID: String? = nil, season: Int? = nil) async throws -> WindowResponse {'
if old in s:
    s = s.replace(old, new, 1)
elif new not in s:
    raise SystemExit('Build 103 client window signature marker missing')
old = '        if let teamID { query.append(.init(name: "team", value: teamID)) }\n        if let leagueID {'
new = '        if let teamID { query.append(.init(name: "team", value: teamID)) }\n        if let teamName, !teamName.isEmpty { query.append(.init(name: "teamName", value: teamName)) }\n        if let leagueID {'
if old in s:
    s = s.replace(old, new, 1)
elif new not in s:
    raise SystemExit('Build 103 teamName query marker missing')
client.write_text(s, encoding="utf-8")

store = Path("Sources/Core/APISportsStore.swift")
s = store.read_text(encoding="utf-8")
old = 'let window = try await CanonicalSportsClient.window(from: from, to: to, teamID: teamID)'
new = 'let window = try await CanonicalSportsClient.window(from: from, to: to, teamID: teamID, teamName: teamName)'
if old in s:
    s = s.replace(old, new, 1)
elif new not in s:
    raise SystemExit('Build 103 team window call marker missing')
store.write_text(s, encoding="utf-8")
print("Build 103 window identity fallback applied")
