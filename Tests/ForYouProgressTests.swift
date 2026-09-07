import Foundation

@main
struct ForYouProgressTests {
    static var count = 0
    static func expect(_ value: @autoclosure () -> Bool, _ label: String) {
        count += 1
        guard value() else { fatalError("FAILED: \(label)") }
    }

    struct Match: FollowedMatchSummary {
        let id: String
        let homeID: String?
        let awayID: String?
        let date: Date?
        let status: String
    }

    static func main() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var state = ForYouProgress<Int>()
        state.select(["3", "1", " 2 ", "1", ""])
        expect(state.teamIDs == ["1", "2", "3"], "selection is unique, trimmed, stable")
        expect(state.pendingIDs(now: now).count == 3, "all clubs are initially pending")
        expect(!state.mayShowEmpty, "unrequested data is not an empty success")
        let first = state.begin("1", now: now)!
        let second = state.begin("2", now: now)!
        expect(state.isLoading, "loading state tracks clubs")
        expect(state.begin("1", now: now) == nil, "duplicate request is coalesced")
        expect(state.begin("404", now: now) == nil, "unfollowed club cannot request")
        expect(state.succeed("1", items: [10], token: first, at: now), "club success applied")
        expect(state.values == [10], "partial results show before other clubs finish")
        expect(state.fail("2", message: "Offline", token: second), "failure is recorded separately")
        expect(state.values == [10], "other club failure does not erase success")
        expect(state.failures == ["2"], "failed club is identified")
        expect(!state.mayShowEmpty, "partial failure is not an empty success")
        expect(state.pendingIDs(now: now) == ["2", "3"], "retry skips fresh successes")
        expect(!state.isLoading, "finished requests leave no spinner")
        let retry = state.begin("2", now: now)!
        expect(state.succeed("2", items: [], token: retry, at: now), "successful empty response retained")
        let third = state.begin("3", now: now)!
        _ = state.succeed("3", items: [], token: third, at: now)
        expect(state.mayShowEmpty, "empty message allowed only after all successful")
        expect(state.hasValue, "successful empties count as received data")
        expect(state.pendingIDs(now: now.addingTimeInterval(299)).isEmpty, "fresh results reused for five minutes")
        expect(state.pendingIDs(now: now.addingTimeInterval(300)).count == 3, "expired results refresh")
        expect(state.pendingIDs(force: true, now: now).count == 3, "manual refresh includes fresh clubs")
        let failedRefresh = state.begin("1", force: true, now: now)!
        _ = state.fail("1", message: "Timeout", token: failedRefresh)
        expect(state.values == [10], "failed refresh retains existing fixtures")
        expect(state.lastUpdated == now, "failed refresh cannot advance freshness")
        expect(state.pendingIDs(now: now) == ["1"], "failed refresh can retry immediately")
        let obsolete = state.begin("1", now: now)!
        state.select(["2", "3"])
        expect(state.values.isEmpty, "unfollow removes fixtures immediately")
        expect(!state.succeed("1", items: [99], token: obsolete, at: now), "late response cannot restore unfollowed club")
        state.select(["1", "2", "3"])
        let newRequest = state.begin("1", now: now)!
        expect(!state.succeed("1", items: [99], token: obsolete, at: now), "refollow still rejects old token")
        expect(state.succeed("1", items: [11], token: newRequest, at: now), "refollow accepts new token")
        state.select((1...9).map(String.init))
        expect(state.teamIDs.count == 9, "more than six followed clubs supported")
        expect(state.pendingIDs(now: now).count == 6, "adding clubs preserves old successes")
        let cancelled = state.begin("4", now: now)!
        state.invalidate()
        expect(!state.isLoading, "leaving page cancels progress")
        expect(!state.fail("4", message: "Cancelled", token: cancelled), "cancelled request cannot display an error")
        expect(state.pendingIDs(now: now).contains("4"), "cancelled club loads again on return")
        let active = state.begin("4", now: now)!
        state.cancel("4", token: cancelled)
        expect(state.state("4").isLoading, "old cleanup cannot stop newer request")
        _ = state.succeed("4", items: [44], token: active, at: now.addingTimeInterval(30))
        expect(state.lastUpdated == now, "oldest successful timestamp is displayed")
        state.select([])
        expect(state.values.isEmpty && !state.hasValue && !state.isLoading, "clearing all follows clears feed")
        expect(!state.mayShowEmpty, "no-follow onboarding is distinct from no fixtures")

        func match(_ id: String, _ status: String, _ offset: Double?, home: String = "1", away: String = "9") -> Match {
            Match(id: id, homeID: home, awayID: away, date: offset.map { now.addingTimeInterval($0) }, status: status)
        }
        let cached = [match("live", "NS", 100), match("old", "NS", -86400), match("next", "NS", 500),
                      match("tbd", "TBD", nil), match("ended", "FT", -200), match("other", "NS", 100, home: "7", away: "8")]
        let today = [match("live", "2H", -1800), match("done", "FT", -3600), match("away", "NS", 300, home: "8", away: "1")]
        let live: (String) -> Bool = { ["1H", "2H", "HT"].contains($0) }
        let merged = ForYouMatchSelection.merge(today: today, upcoming: cached, teamIDs: ["1"], startOfToday: now.addingTimeInterval(-43200), isLive: live)
        expect(merged.first?.id == "live", "live match ranks above upcoming and completed")
        expect(merged.first?.status == "2H", "today replaces outdated upcoming status")
        expect(merged.filter { $0.id == "live" }.count == 1, "same fixture shown once")
        expect(!merged.contains { $0.id == "old" }, "yesterday's cached upcoming fixture excluded")
        expect(!merged.contains { $0.id == "ended" }, "finished upcoming cache excluded")
        expect(!merged.contains { $0.id == "other" }, "unfollowed teams excluded")
        expect(merged.map(\.id) == ["live", "away", "next", "tbd", "done"], "chronology, away follow, and unknown kickoff ordering")
        expect(ForYouMatchSelection.merge(today: today, upcoming: cached, teamIDs: [], startOfToday: now, isLive: live).isEmpty, "empty selection has no stale matches")
        let twice = ForYouMatchSelection.merge(today: [], upcoming: [match("same", "NS", 10), match("same", "NS", 10)], teamIDs: ["1", "9"], startOfToday: now, isLive: live)
        expect(twice.count == 1, "following both teams still shows one fixture")
        let tie = ForYouMatchSelection.merge(today: [], upcoming: [match("b", "NS", 10), match("a", "NS", 10)], teamIDs: ["1"], startOfToday: now, isLive: live)
        expect(tie.map(\.id) == ["a", "b"], "equal kickoff order is stable")
        print("PASS: \(count) For You state and selection checks")
    }
}
