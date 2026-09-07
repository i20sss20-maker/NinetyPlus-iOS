import Foundation

@main
struct PageResourceTests {
    static func main() {
        var passed = 0
        func check(_ condition: Bool, _ name: String) {
            precondition(condition, "FAIL: \(name)")
            passed += 1
            print("PASS: \(name)")
        }
        let stamp = Date(timeIntervalSince1970: 1000)
        var state = PageResource<[Int]>()
        check(state.value == nil && !state.isLoading, "Initial state is not an empty success")
        let first = state.begin(key: "day-a")
        check(state.isLoading, "Begin marks loading")
        state.succeed([1, 2], token: first, at: stamp)
        check(state.value == [1, 2] && state.lastUpdated == stamp, "Success stores data and fetch time")
        let refresh = state.begin(key: "day-a")
        check(state.value == [1, 2] && state.isLoading, "Same-resource refresh keeps visible data")
        state.fail("offline", token: refresh)
        check(state.value == [1, 2] && state.lastUpdated == stamp && state.errorMessage == "offline", "Failure preserves data and successful timestamp")
        check(!state.isFresh(key: "day-a", maxAge: 90, now: stamp), "Failed refresh remains retryable")
        let older = state.begin(key: "day-a")
        let newer = state.begin(key: "day-a")
        check(!state.succeed([99], token: older), "Older same-key completion is rejected")
        state.cancel(token: older)
        check(state.isLoading, "Older cancellation cannot stop the current loader")
        state.succeed([], token: newer, at: stamp)
        check(state.value != nil && state.value!.isEmpty && state.errorMessage == nil, "Successful empty result stays distinguishable from error")
        check(state.isFresh(key: "day-a", maxAge: 90, now: stamp.addingTimeInterval(10)), "Empty success is cached too")
        check(!state.isFresh(key: "day-a", maxAge: 90, now: stamp.addingTimeInterval(90)), "Expired result must reload")
        check(!state.isFresh(key: "day-a", maxAge: 90, now: stamp.addingTimeInterval(-1)), "Clock rollback does not create immortal cache")
        let dateA = state.begin(key: "day-a")
        let dateB = state.begin(key: "day-b")
        check(state.value == nil && state.lastUpdated == nil, "Switching date clears mismatched data")
        check(!state.fail("old error", token: dateA), "Previous date cannot overwrite current error")
        state.cancel(token: dateB)
        check(!state.isLoading && state.errorMessage == nil, "Cancellation is not shown as network failure")
        check(!state.succeed([9], token: dateB), "Late completion after cancellation is ignored")
        let hidden = state.begin(key: "day-b")
        state.invalidate()
        check(!state.succeed([5], token: hidden), "Hidden page ignores pending completion")
        var favorites = PageResource<[String]>()
        let seed = favorites.begin(key: "team:1")
        favorites.succeed(["1"], token: seed, at: stamp)
        let changed = favorites.begin(key: "team:1,2", retainingValue: true)
        check(favorites.value == ["1"] && favorites.lastUpdated == nil, "Favorite changes can preserve known profiles without claiming a fresh fetch")
        favorites.succeed(["1", "2"], token: changed, warning: "partial", at: stamp)
        check(favorites.errorMessage == "partial" && favorites.value?.count == 2, "Partial success keeps both data and warning")
        check(!favorites.isFresh(key: "team:1,2", maxAge: 90, now: stamp), "Partial failure stays retryable")
        check(SavedFavoriteIDs.parse(" 2,1,2,, 3 , ") == ["1", "2", "3"], "Favorite IDs are deduplicated and stable")
        check(FixturePhase.isUpcoming("ns") && FixturePhase.isUpcoming("TBD"), "Scheduled fixtures count as upcoming")
        check(!FixturePhase.isUpcoming("CANC") && !FixturePhase.isUpcoming("PST") && !FixturePhase.isUpcoming("1H"), "Cancelled, postponed and live fixtures are not upcoming")
        check(FixturePhase.isFinished("FT") && FixturePhase.isFinished("AET") && FixturePhase.isFinished("PEN") && !FixturePhase.isFinished("P"), "Final and active penalty phases are distinct")
        print("\(passed) PageResource checks passed")
    }
}
