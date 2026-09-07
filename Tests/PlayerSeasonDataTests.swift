import Foundation

@main enum PlayerSeasonDataTests {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); checks += 1
        }
        func games(_ json: String) throws -> APITopScorerItem.Statistic.Games {
            try JSONDecoder().decode(APITopScorerItem.Statistic.Games.self, from: Data(json.utf8))
        }
        let documented = try games(#"{"appearences":21,"minutes":1700,"rating":"7.49","position":"Attacker"}"#)
        check(documented.appearances == 21, "The documented appearences key must not decode as nil")
        check(documented.minutes == 1700, "Minutes preserved")
        check(documented.rating == "7.49", "Rating preserved")
        check(documented.position == "Attacker", "Position preserved")
        let alternate = try games(#"{"appearances":12}"#)
        check(alternate.appearances == 12, "Conventional spelling accepted")
        let null = try games(#"{"appearences":null,"appearances":12,"minutes":null}"#)
        check(null.appearances == nil, "Explicit provider null takes precedence over an alternate field")
        check(null.minutes == nil, "Null minutes are not zero")
        let empty = try games("{}")
        check(empty.appearances == nil, "Missing appearances are unknown")
        let zero = try games(#"{"appearences":0,"minutes":0}"#)
        check(zero.appearances == 0 && zero.minutes == 0, "Actual zero preserved")
        do { _ = try games(#"{"appearences":"broken"}"#); preconditionFailure("Invalid type silently accepted") }
        catch { checks += 1 }
        let payload = #"{"player":{"id":123,"name":"Test"},"statistics":[{"team":{"id":1,"name":"Team"},"league":{"id":2,"name":"League"},"games":{"appearences":21,"minutes":1700},"goals":{"total":4,"assists":null},"cards":{"yellow":0,"red":null}},{"team":{}}]}"#
        let item = try JSONDecoder().decode(APITopScorerItem.self, from: Data(payload.utf8))
        let stat = APIPlusPlayerSeasonStat(playerID: "123", season: 2025, index: 0, statistic: item.statistics[0])
        check(stat.season == 2025, "The season travels with the statistics")
        check(stat.appearances == 21, "Decoded appearances reach presentation model")
        check(stat.goals == 4, "Goals preserved")
        check(stat.assists == nil, "Unreported assists stay unknown")
        check(stat.yellowCards == 0 && stat.redCards == nil, "Known and unknown cards remain distinct")
        let missing = APIPlusPlayerSeasonStat(playerID: "123", season: 2025, index: 1, statistic: item.statistics[1])
        check(missing.appearances == nil && missing.minutes == nil && missing.goals == nil && missing.assists == nil, "Missing groups do not manufacture four zeros")
        check(missing.teamID == nil, "Missing ID must not become an invented team ID")
        check(stat.id != missing.id, "Separate competition rows have separate identities")
        check(SeasonCopy.label(2025) == "2025–26", "Season start year is labelled as the actual football season")
        check(SeasonCopy.label(2026) == "2026–27", "Current season label increments correctly")
        check(SportsCopy.metric(nil) == "—", "Unknown metric displays dash")
        check(SportsCopy.metric(0) == "0", "Actual zero displays zero")
        check(SportsCopy.metric(21) == "21", "Actual count is displayed")
        check(SportsCopy.metric(-1) == "—", "Invalid negative count is not displayed")
        print("PASS: \(checks) player decoding, season and missing-value checks")
    }
}
