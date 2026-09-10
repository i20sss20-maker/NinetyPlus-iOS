import Foundation

enum FreeMatchDetail {
    static func load(_ match: APIPlusMatch) async throws -> CanonicalSportsClient.MatchDetail {
        let parts = match.id.split(separator: ":").map(String.init)
        guard parts.count == 3, parts[0] == "espn",
              PublicScoreboardSource.leagues.contains(where: { $0.espnCode == parts[1] }),
              parts[2].allSatisfy({ $0.isASCII && $0.isNumber }) else { throw APIFootballError.badResponse }
        let url = URL(string: "https://site.web.api.espn.com/apis/site/v2/sports/soccer/\(parts[1])/summary?event=\(parts[2])")!
        var request = URLRequest(url: url); request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw APIFootballError.serviceUnavailable }
        return try decode(data, seed: match)
    }
    static func decode(_ data: Data, seed: APIPlusMatch) throws -> CanonicalSportsClient.MatchDetail {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let header = root["header"] as? [String: Any],
              let eventID = header["id"] as? String, seed.id.hasSuffix(":" + eventID) else { throw APIFootballError.badResponse }
        func dict(_ value: Any?) -> [String: Any] { value as? [String: Any] ?? [:] }
        func array(_ value: Any?) -> [[String: Any]] { value as? [[String: Any]] ?? [] }
        func text(_ value: Any?) -> String? { value as? String }
        func clean(_ value: [String: Any?]) -> [String: Any] { value.compactMapValues { $0 } }
        let competition = array(header["competitions"]).first ?? [:]
        let competitors = array(competition["competitors"])
        let home = competitors.first { text($0["homeAway"]) == "home" } ?? [:]
        let away = competitors.first { text($0["homeAway"]) == "away" } ?? [:]
        let status = dict(competition["status"])
        let type = dict(status["type"])
        let state = text(type["state"]) ?? ""
        let statusText = text(type["description"]) ?? ""
        let code = PublicScoreboardSource.mappedStatus(state: state, completed: type["completed"] as? Bool ?? false,
            description: statusText, detail: text(type["detail"]), name: text(type["name"]))
        let started = !["NS", "TBD", "PST", "CANC"].contains(code)
        func score(_ object: [String: Any]) -> Int? {
            if let value = object["score"] as? String { return Int(value) }
            return object["score"] as? Int
        }
        var fixture: [String: Any] = [
            "canonicalId": seed.id,
            "league": clean(["id": seed.leagueID, "name": seed.league, "logo": seed.leagueLogo]),
            "home": clean(["id": seed.homeID, "name": seed.home, "logo": seed.homeLogo]),
            "away": clean(["id": seed.awayID, "name": seed.away, "logo": seed.awayLogo]),
            "score": clean(["home": started ? score(home) : nil, "away": started ? score(away) : nil]),
            "status": clean(["code": code, "text": statusText,
                "elapsed": state == "in" ? text(status["displayClock"]).flatMap { Int($0.prefix { $0.isNumber }) } : nil]),
            "providerIds": ["espn": eventID], "sources": ["ESPN"]
        ]
        fixture["dateUTC"] = competition["date"] ?? seed.date.map { ISO8601DateFormatter().string(from: $0) }
        let events = array(root["keyEvents"] ?? root["plays"]).map { item in
            clean(["minute": text(dict(item["clock"])["displayValue"]),
                   "type": text(dict(item["type"])["text"]) ?? text(dict(item["type"])["name"]),
                   "text": text(item["text"]) ?? text(item["shortText"]),
                   "team": text(dict(item["team"])["displayName"])])
        }
        // IDs inside these detail sections are deliberately omitted: ESPN player
        // IDs cannot be used to open API-Football profiles.
        let statistics = array(dict(root["boxscore"])["teams"]).map { item -> [String: Any] in
            let team = dict(item["team"])
            return ["team": clean(["name": text(team["displayName"]), "logo": text(team["logo"])]),
                "statistics": array(item["statistics"]).map { clean(["name": $0["label"] ?? $0["name"], "value": $0["displayValue"] ?? $0["value"]]) }]
        }
        let lineups = array(root["rosters"]).map { item -> [String: Any] in
            let team = dict(item["team"])
            return clean(["team": clean(["name": text(team["displayName"]), "logo": text(team["logo"])]),
                "formation": text(item["formation"]),
                "players": array(item["roster"]).map { row in
                    let athlete = dict(row["athlete"])
                    return clean(["name": text(athlete["displayName"]), "jersey": athlete["jersey"] ?? row["jersey"],
                        "position": text(dict(athlete["position"])["abbreviation"]), "starter": row["starter"] ?? row["isStarter"]])
                }])
        }
        let payload: [String: Any] = ["match": fixture, "events": events, "statistics": statistics, "lineups": lineups,
            "coverage": clean(["events": events.isEmpty ? nil : "ESPN", "statistics": statistics.isEmpty ? nil : "ESPN", "lineups": lineups.isEmpty ? nil : "ESPN"])]
        return try JSONDecoder().decode(CanonicalSportsClient.MatchDetail.self, from: JSONSerialization.data(withJSONObject: payload))
    }
}
