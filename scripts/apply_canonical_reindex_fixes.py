from pathlib import Path

client = Path("Sources/Core/CanonicalSportsClient.swift")
client_text = client.read_text()
view = Path("Sources/Views/V2MatchExperience.swift")
view_text = view.read_text()

# The release transformation already installs date-aware canonical detail loading.
# Keep this separate guard so future refactors cannot silently remove self-healing
# after a Railway restart.
required_client = [
    'static func detail(matchID: String, date: Date? = nil) async throws -> MatchDetail',
    'query.append(.init(name: "date", value: formatter.string(from: date)))',
    'return try await get("api/v2/match", query: query)',
]
required_view = 'CanonicalSportsClient.detail(matchID: match.id, date: match.date)'

missing = [marker for marker in required_client if marker not in client_text]
if required_view not in view_text:
    missing.append(required_view)
if missing:
    raise SystemExit("canonical reindex guard missing: " + " | ".join(missing))

print("Verified self-healing canonical match ID + date forwarding")
