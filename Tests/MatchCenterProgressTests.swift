import Foundation

@main
struct MatchCenterProgressTests {
    static var checks = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        guard value() else { fatalError(message) }
        checks += 1
    }
    static func main() {
        let now = Date(timeIntervalSince1970: 100000)
        var state = MatchCenterProgress()
        expect(state.begin(.fixture) == nil, "A match must be selected first")
        state.select(matchID: "100")
        let fixture = state.begin(.fixture, now: now)!
        let stats = state.begin(.stats, now: now)!
        expect(state.begin(.fixture, now: now) == nil, "Do not duplicate an in-flight endpoint")
        state.succeed(.fixture, token: fixture, hasContent: true, at: now)
        expect(state.state(.fixture).value == true, "Score can arrive while statistics are still loading")
        expect(state.state(.stats).isLoading, "Other requests remain independent")
        state.fail(.stats, token: stats, message: "offline")
        expect(state.state(.fixture).lastUpdated == now, "Stats failure must not change score time")
        expect(!state.mayShowEmpty(.stats), "A failed request is not an empty result")
        expect(state.state(.stats).lastUpdated == nil, "Failed first load never looks freshly updated")
        let events = state.begin(.events, now: now)!
        state.succeed(.events, token: events, hasContent: false, at: now)
        expect(state.mayShowEmpty(.events), "An actual empty response can show the empty state")
        expect(state.errors.count == 1 && state.errors.first?.0 == .stats, "Do not erase another section's error")
        expect(!state.select(matchID: "100"), "Retrying same match retains data")
        expect(state.state(.fixture).value == true, "Retry does not reset the current score")
        expect(state.begin(.fixture, now: now.addingTimeInterval(1)) == nil, "Reuse fresh score")
        let retry = state.begin(.fixture, force: true, now: now)!
        state.fail(.fixture, token: retry, message: "timeout")
        expect(state.state(.fixture).value == true, "Failed refresh retains last valid score")
        expect(state.state(.fixture).lastUpdated == now, "Failed refresh retains last successful timestamp")
        let older = state.begin(.fixture, force: true, now: now)!
        let newer = state.begin(.fixture, force: true, now: now)!
        state.succeed(.fixture, token: newer, hasContent: true, at: now.addingTimeInterval(30))
        expect(!state.succeed(.fixture, token: older, hasContent: false, at: now), "Old response cannot replace a newer score")
        state.fail(.fixture, token: older, message: "late error")
        expect(state.state(.fixture).errorMessage == nil, "Old failure cannot overwrite new success")
        let pending = state.begin(.lineups, now: now)!
        state.invalidate()
        expect(!state.succeed(.lineups, token: pending, hasContent: true, at: now), "Backgrounded page rejects late completions")
        expect(!state.state(.lineups).isLoading, "Cancellation clears spinner")
        expect(state.state(.lineups).errorMessage == nil, "Cancellation is not an outage")
        let oldMatch = state.begin(.events, force: true, now: now)!
        state.select(matchID: "200")
        expect(!state.succeed(.events, token: oldMatch, hasContent: true, at: now), "Old match cannot populate another match")
        expect(state.state(.fixture).value == nil, "No previous score leaks into a new match")
        state.markUnavailable(.h2h)
        expect(state.mayShowEmpty(.h2h), "Missing team identifiers are unavailable, not an outage")
        expect(state.state(.h2h).lastUpdated == nil, "Skipped calls must not claim a fresh response")
        state.markAvailable(.h2h)
        expect(state.begin(.h2h, now: now) != nil, "H2H can load after team identifiers arrive")

        expect(MatchLivePolicy.notice(previousStatus: "NS", status: "1H", previousHome: nil, previousAway: nil, home: 0, away: 0) == .started, "Kickoff is not a goal")
        expect(MatchLivePolicy.notice(previousStatus: "HT", status: "2H", previousHome: 0, previousAway: 0, home: 0, away: 0) == nil, "Second half is not another kickoff")
        expect(MatchLivePolicy.notice(previousStatus: "1H", status: "HT", previousHome: 1, previousAway: 0, home: 1, away: 0) == nil, "Halftime is not another kickoff")
        expect(MatchLivePolicy.notice(previousStatus: "2H", status: "FT", previousHome: 1, previousAway: 1, home: 2, away: 1) == .finished, "Final whistle takes priority over a simultaneous score change")
        expect(MatchLivePolicy.notice(previousStatus: "2H", status: "2H", previousHome: 1, previousAway: 1, home: 2, away: 1) == .scoreChanged, "A known score change is detected")
        expect(MatchLivePolicy.notice(previousStatus: "1H", status: "1H", previousHome: nil, previousAway: nil, home: 0, away: 0) == nil, "Unknown to zero is not a goal")
        expect(MatchLivePolicy.notice(previousStatus: "FT", status: "AET", previousHome: 1, previousAway: 1, home: 1, away: 1) == nil, "Do not repeat finished notification")
        expect(MatchLivePolicy.interval(status: "2H", kickoff: nil, now: now) == 30, "Live polling cadence")
        expect(MatchLivePolicy.interval(status: "FT", kickoff: nil, now: now) == nil, "Stop after full time")
        expect(MatchLivePolicy.interval(status: "PEN", kickoff: nil, now: now) == nil, "Finished penalties are not live")
        expect(MatchLivePolicy.interval(status: "PST", kickoff: nil, now: now) == nil, "No rapid polling of postponed matches")
        expect(MatchLivePolicy.interval(status: "NS", kickoff: now.addingTimeInterval(86400), now: now) == 300, "Slow down for future matches")
        expect(MatchLivePolicy.interval(status: "NS", kickoff: now.addingTimeInterval(300), now: now) == 30, "Check near kickoff")
        expect(MatchLivePolicy.statusText("HT", elapsed: 45) == "بين الشوطين", "Halftime label wins over generic live")
        expect(MatchLivePolicy.statusText("AET", elapsed: 120).hasPrefix("انتهت"), "Extra-time completion is explicit")
        expect(MatchLivePolicy.statusText("P", elapsed: 120) != MatchLivePolicy.statusText("PEN", elapsed: 120), "Penalty play differs from penalty completion")
        expect(MatchLivePolicy.eventMinute(elapsed: 90, extra: 4) == "90+4′", "Display added time")
        expect(MatchLivePolicy.eventMinute(elapsed: nil, extra: nil) == "—", "Unknown minute is not zero")
        expect(MatchLivePolicy.summary(status: "FT", homeName: "Home", awayName: "Away", home: 2, away: 1).contains("بفوز"), "Finished winner is not described as still leading")
        expect(MatchLivePolicy.summary(status: "PEN", homeName: "Home", awayName: "Away", home: 1, away: 1).contains("لا تحدد"), "Do not invent the shootout winner")
        expect(MatchLivePolicy.summary(status: "NS", homeName: "Home", awayName: "Away", home: 0, away: 0).contains("لم تبدأ"), "Pre-match zeroes are not a live draw")
        print("PASS: \(checks) match center state and policy checks")
    }
}
