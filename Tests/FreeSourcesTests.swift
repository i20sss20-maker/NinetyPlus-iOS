import Foundation

@main struct FreeSourcesTests {
    static func main() async throws {
        let suite = "free-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let date = ISO8601DateFormatter().date(from: "2026-09-10T21:30:00Z")!
        assert(FreeFixtureFeed.key(date) == "2026-09-11", "Riyadh day must not become yesterday in UTC")
        let value = APIPlusMatch(id: "espn:uefa.champions:401915444", leagueID: "2", league: "Champions League", leagueLogo: nil,
            homeID: nil, home: "Fenerbahce", homeLogo: nil, awayID: nil, away: "Roma", awayLogo: nil,
            homeScore: 1, awayScore: 1, date: date, status: "FT", elapsed: nil)
        let first = FreeFixtureFeed(defaults: defaults, loader: { _, _ in [value] })
        let saved = try await first.snapshot(date: date, now: date)
        assert(saved.warning == nil && saved.matches.count == 1)
        let offline = FreeFixtureFeed(defaults: defaults, loader: { _, _ in throw URLError(.notConnectedToInternet) })
        let recovered = try await offline.snapshot(date: date, force: true, now: date.addingTimeInterval(120))
        assert(recovered.matches.first?.id == value.id && recovered.fetchedAt == date && recovered.warning != nil)
        do {
            _ = try await offline.snapshot(date: date.addingTimeInterval(86400), force: true, now: date.addingTimeInterval(120))
            assertionFailure("Never show a different day's cache")
        } catch {}
        do {
            _ = try await offline.snapshot(date: date, force: true, now: date.addingTimeInterval(8 * 86400))
            assertionFailure("Expired cache must not look like current data")
        } catch {}
        let empty = FreeFixtureFeed(defaults: defaults, loader: { _, _ in [] })
        let result = try await empty.snapshot(date: date, force: true, now: date.addingTimeInterval(180))
        assert(result.matches.isEmpty && result.warning == nil)
        do { _ = try FreeSportsDirectory.identifier("874"); assertionFailure("Foreign IDs must be rejected") } catch {}
        let playerID = try FreeSportsDirectory.identifier("tsdb:34146304")
        assert(playerID == "34146304")
        let detail = try FreeMatchDetail.decode(Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/free-summary.json")), seed: value)
        assert(detail.appLineups.count == 2)
        assert(detail.appLineups.allSatisfy { $0.startXI?.count == 11 })
        assert(detail.appLineups.allSatisfy { $0.startXI?.allSatisfy { $0.player.id == nil } == true })
        assert(!detail.appStatistics.isEmpty && !detail.appEvents.isEmpty)
        print("PASS: free fixtures persist across instances, stale warning/timestamp, day isolation, expiry, empty days, source IDs and real match details")
    }
}
