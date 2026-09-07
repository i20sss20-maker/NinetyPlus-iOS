from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f"canonical reindex patch missing: {label}")
    return text.replace(old, new, 1)

client = Path("Sources/Core/CanonicalSportsClient.swift")
s = client.read_text()
s = replace_once(
    s,
    '''    static func detail(matchID: String) async throws -> MatchDetail {\n        try await get("api/v2/match", query: [.init(name: "id", value: matchID)])\n    }''',
    '''    static func detail(match: APIPlusMatch) async throws -> MatchDetail {\n        var query = [URLQueryItem(name: "id", value: match.id)]\n        if let kickoff = match.date {\n            let formatter = DateFormatter()\n            formatter.locale = Locale(identifier: "en_US_POSIX")\n            formatter.calendar = Calendar(identifier: .gregorian)\n            formatter.timeZone = TimeZone(identifier: "Asia/Riyadh")\n            formatter.dateFormat = "yyyy-MM-dd"\n            query.append(URLQueryItem(name: "date", value: formatter.string(from: kickoff)))\n        }\n        return try await get("api/v2/match", query: query)\n    }''',
    "canonical detail date"
)
client.write_text(s)

view = Path("Sources/Views/V2MatchExperience.swift")
s = view.read_text()
s = replace_once(
    s,
    'let detail = try await CanonicalSportsClient.detail(matchID: match.id)',
    'let detail = try await CanonicalSportsClient.detail(match: match)',
    "canonical detail call"
)
view.write_text(s)
print("Applied self-healing canonical match reindex date forwarding")
