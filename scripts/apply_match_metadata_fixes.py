from pathlib import Path


def replace_once(old: str, new: str, label: str) -> str:
    global s
    if new in s:
        return s
    if old not in s:
        raise SystemExit(f"metadata patch pattern missing: {label}")
    return s.replace(old, new, 1)

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
s = replace_once(
'''                    HStack {\n                        RemoteBadge(url: lineup.team.logo).frame(width: 40, height: 40)\n                        VStack(alignment: .leading, spacing: 2) {\n                            Text(SportsArabic.team(lineup.team.name ?? "فريق")).font(.headline)\n                            Text("الخطة \\(lineup.formation ?? "—")").font(.caption).foregroundStyle(AppTheme.green)\n                        }\n                        Spacer()\n                    }\n                    ForEach(Array((lineup.startXI ?? []).enumerated()), id: \\.offset) { _, slot in\n                        HStack(spacing: 10) {\n                            Text(slot.player.number.map(String.init) ?? "—")\n                                .font(.caption.bold()).foregroundStyle(AppTheme.green)\n                                .frame(width: 30, height: 30)\n                                .background(AppTheme.green.opacity(0.10), in: Circle())\n                            Text(slot.player.name ?? "لاعب").font(.subheadline.weight(.medium))\n                            Spacer()\n                            Text(positionText(slot.player.pos)).font(.caption).foregroundStyle(AppTheme.muted)\n                        }\n                    }''',
'''                    HStack {\n                        RemoteBadge(url: lineup.team.logo).frame(width: 40, height: 40)\n                        VStack(alignment: .leading, spacing: 3) {\n                            Text(SportsArabic.team(lineup.team.name ?? "فريق")).font(.headline)\n                            Text("الخطة \\(lineup.formation ?? "—")").font(.caption).foregroundStyle(AppTheme.green)\n                            if let coach = lineup.coach?.name, !coach.isEmpty {\n                                Text("المدرب: \\(coach)").font(.caption2).foregroundStyle(AppTheme.muted)\n                            }\n                        }\n                        Spacer()\n                    }\n                    Text("التشكيلة الأساسية").font(.caption.bold()).foregroundStyle(AppTheme.muted)\n                    ForEach(Array((lineup.startXI ?? []).enumerated()), id: \\.offset) { _, slot in\n                        lineupPlayerRow(slot)\n                    }\n                    if let substitutes = lineup.substitutes, !substitutes.isEmpty {\n                        Divider().overlay(AppTheme.border)\n                        Text("البدلاء").font(.caption.bold()).foregroundStyle(AppTheme.muted)\n                        ForEach(Array(substitutes.enumerated()), id: \\.offset) { _, slot in\n                            lineupPlayerRow(slot)\n                        }\n                    }''',
'lineup coach substitutes'
)
s = replace_once(
'''    private func positionText(_ value: String?) -> String {''',
'''    private func lineupPlayerRow(_ slot: APILineupItem.Slot) -> some View {\n        HStack(spacing: 10) {\n            Text(slot.player.number.map(String.init) ?? "—")\n                .font(.caption.bold()).foregroundStyle(AppTheme.green)\n                .frame(width: 30, height: 30)\n                .background(AppTheme.green.opacity(0.10), in: Circle())\n            Text(slot.player.name ?? "لاعب").font(.subheadline.weight(.medium))\n            Spacer()\n            Text(positionText(slot.player.pos)).font(.caption).foregroundStyle(AppTheme.muted)\n        }\n    }\n\n    private func positionText(_ value: String?) -> String {''',
'lineup row helper'
)
match.write_text(s)
print("Applied canonical match metadata fixes, coaches and substitutes")
