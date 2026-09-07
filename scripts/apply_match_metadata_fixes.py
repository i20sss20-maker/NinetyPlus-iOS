from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f"metadata patch pattern missing: {label}")
    return text.replace(old, new, 1)

client = Path("Sources/Core/CanonicalSportsClient.swift")
s = client.read_text()
s = replace_once(
'''        let coverage: Coverage?\n        let generatedAt: String?\n        struct Coverage: Decodable { let events: String?; let statistics: String?; let lineups: String? }''',
'''        let coverage: Coverage?\n        let venue: Venue?\n        let officials: [Official]?\n        let generatedAt: String?\n        struct Coverage: Decodable { let events: String?; let statistics: String?; let lineups: String? }\n        struct Venue: Decodable { let name: String?; let city: String?; let country: String? }\n        struct Official: Decodable { let name: String?; let role: String? }\n\n        var venueText: String? {\n            guard let venue else { return nil }\n            let parts = [venue.name, venue.city].compactMap { value in\n                value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? value : nil\n            }\n            return parts.isEmpty ? nil : parts.joined(separator: " • ")\n        }\n        var refereeText: String? {\n            guard let official = officials?.first(where: { item in\n                let role = item.role?.lowercased() ?? ""\n                return role.contains("ref") || role.contains("حكم")\n            }) ?? officials?.first else { return nil }\n            return official.name\n        }''',
'match detail metadata'
)
s = replace_once(
'''    static func detail(matchID: String) async throws -> MatchDetail {\n        try await get("api/v2/match", query: [.init(name: "id", value: matchID)])\n    }''',
'''    static func detail(matchID: String, date: Date? = nil) async throws -> MatchDetail {\n        var query = [URLQueryItem(name: "id", value: matchID)]\n        if let date {\n            let formatter = DateFormatter()\n            formatter.locale = Locale(identifier: "en_US_POSIX")\n            formatter.calendar = Calendar(identifier: .gregorian)\n            formatter.timeZone = TimeZone(secondsFromGMT: 0)\n            formatter.dateFormat = "yyyy-MM-dd"\n            query.append(.init(name: "date", value: formatter.string(from: date)))\n        }\n        return try await get("api/v2/match", query: query)\n    }''',
'dated canonical detail'
)
client.write_text(s)

match = Path("Sources/Views/V2MatchExperience.swift")
s = match.read_text()
s = replace_once(
'''    @Published private(set) var h2h: [APIPlusMatch] = []\n    @Published private(set) var progress = MatchCenterProgress()''',
'''    @Published private(set) var h2h: [APIPlusMatch] = []\n    @Published private(set) var venue: String?\n    @Published private(set) var referee: String?\n    @Published private(set) var progress = MatchCenterProgress()''',
'store metadata fields'
)
s = replace_once(
'''        events = []; stats = []; lineups = []; h2h = []\n        lastObserved = nil''',
'''        events = []; stats = []; lineups = []; h2h = []\n        venue = nil; referee = nil\n        lastObserved = nil''',
'reset metadata'
)
s = replace_once(
'''            let detail = try await CanonicalSportsClient.detail(matchID: match.id)''',
'''            let detail = try await CanonicalSportsClient.detail(matchID: match.id, date: match.date)''',
'dated detail call'
)
s = replace_once(
'''            let newLineups = detail.appLineups\n            if let token = tokens[.lineups], progress.succeed(.lineups, token: token, hasContent: !newLineups.isEmpty) { lineups = newLineups }''',
'''            let newLineups = detail.appLineups\n            if let token = tokens[.lineups], progress.succeed(.lineups, token: token, hasContent: !newLineups.isEmpty) { lineups = newLineups }\n            venue = detail.venueText\n            referee = detail.refereeText''',
'assign match metadata'
)
s = replace_once(
'''                if let date = m.date {\n                    Divider().overlay(AppTheme.border)\n                    infoRow("الموعد", SportsDisplayDate.label(date, pattern: "d MMMM yyyy، HH:mm"))\n                }\n            }''',
'''                if let date = m.date {\n                    Divider().overlay(AppTheme.border)\n                    infoRow("الموعد", SportsDisplayDate.label(date, pattern: "d MMMM yyyy، HH:mm"))\n                }\n                if let venue = store.venue, !venue.isEmpty {\n                    Divider().overlay(AppTheme.border)\n                    infoRow("الملعب", venue)\n                }\n                if let referee = store.referee, !referee.isEmpty {\n                    Divider().overlay(AppTheme.border)\n                    infoRow("الحكم", referee)\n                }\n            }''',
'overview venue referee'
)
match.write_text(s)
print("Applied canonical match metadata fixes")
