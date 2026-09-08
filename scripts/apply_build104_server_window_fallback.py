"""Build 104: keep club window fallback inside Railway as one client request.

The backend can match fallback ESPN/canonical fixtures by normalized team name when
provider IDs differ. The iOS client therefore sends teamName with the window call.
"""
from pathlib import Path


def replace_once(text, old, new, label):
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f"Build 104 patch marker missing: {label}")
    return text.replace(old, new, 1)

client = Path("Sources/Core/CanonicalSportsClient.swift")
s = client.read_text(encoding="utf-8")
old = 'static func window(from: Date, to: Date, teamID: String? = nil, leagueID: String? = nil, season: Int? = nil) async throws -> WindowResponse {'
new = 'static func window(from: Date, to: Date, teamID: String? = nil, teamName: String? = nil, leagueID: String? = nil, season: Int? = nil) async throws -> WindowResponse {'
s = replace_once(s, old, new, "window signature")
old = '        if let teamID { query.append(.init(name: "team", value: teamID)) }\n        if let leagueID {'
new = '        if let teamID { query.append(.init(name: "team", value: teamID)) }\n        if let teamName, !teamName.isEmpty { query.append(.init(name: "teamName", value: teamName)) }\n        if let leagueID {'
s = replace_once(s, old, new, "teamName query")
client.write_text(s, encoding="utf-8")

store = Path("Sources/Core/APISportsStore.swift")
s = store.read_text(encoding="utf-8")
old = 'let window = try await CanonicalSportsClient.window(from: from, to: to, teamID: teamID)'
new = 'let window = try await CanonicalSportsClient.window(from: from, to: to, teamID: teamID, teamName: teamName)'
s = replace_once(s, old, new, "coalesced team window call")
store.write_text(s, encoding="utf-8")

print("Build 104 server-side window fallback client wiring applied")
