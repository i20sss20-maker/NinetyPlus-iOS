import Foundation

@main struct PublicSourceTests {
    static func main() throws {
        let now = ISO8601DateFormatter().date(from: "2026-09-07T12:00:00Z")!
        func document(start: String = "2026-07-01T04:00Z", end: String = "2027-07-01T03:59Z", duplicate: Bool = false) throws -> Data {
            let row: [String: Any] = ["team": ["id": "929", "displayName": "Club", "logos": [], "links": []], "stats": [["name": "points", "value": 15.0, "displayValue": "15"]]]
            let rows = duplicate ? [row, row] : [row]
            return try JSONSerialization.data(withJSONObject: ["name": "League", "season": ["year": 2026, "startDate": start, "endDate": end], "children": [["name": "League", "standings": ["season": 2026, "entries": rows]]]])
        }
        let table = try PublicLeagueTable.decodeCurrent(document(), now: now)
        let row = table.children[0].standings.entries[0]
        precondition(row.id == "espn:929")
        precondition(row.display("points") == "15")
        precondition(row.display("wins") == "—")
        precondition(row.sourceURL == nil)
        precondition(PublicLeagueSource.code(for: "307") == "ksa.1")
        precondition(PublicLeagueSource.code(for: "unknown") == nil)
        do { _ = try PublicLeagueTable.decodeCurrent(document(start: "2024-07-01T04:00Z", end: "2025-07-01T03:59Z"), now: now); fatalError("Old season was relabeled current") } catch {}
        do { _ = try PublicLeagueTable.decodeCurrent(document(start: "2027-07-01T04:00Z", end: "2028-07-01T03:59Z"), now: now); fatalError("Future season accepted") } catch {}
        do { _ = try PublicLeagueTable.decodeCurrent(document(duplicate: true), now: now); fatalError("Duplicate source IDs accepted") } catch {}
        precondition(SportsDisplayDate.calendar.component(.year, from: now) == 2026)
        precondition(SportsDisplayDate.label(now).contains("سبتمبر"))
        if CommandLine.arguments.count > 1 {
            let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            let actual = try PublicLeagueTable.decodeCurrent(data)
            precondition(!actual.children.flatMap { $0.standings.entries }.isEmpty)
            print("LIVE: current source season \(actual.season.year), \(actual.children[0].standings.entries.count) rows")
        }
        print("PASS: 11 current-season, identifier, missing-statistic and Gregorian-date checks")
    }
}
