import Foundation
#if canImport(ActivityKit)
import ActivityKit

@available(iOS 16.1, *)
@MainActor
enum LiveMatchActivityCoordinator {
    private static var activities: [String: Activity<NinetyPlusMatchActivityAttributes>] = [:]

    static func startOrUpdate(match: APIPlusMatch) async {
        let state = NinetyPlusMatchActivityAttributes.ContentState(
            homeScore: match.homeScore,
            awayScore: match.awayScore,
            status: MatchLivePolicy.statusText(match.status, elapsed: match.elapsed).englishDigits,
            elapsed: match.elapsed,
            updatedAt: Date()
        )
        if let activity = activities[match.id] ?? Activity<NinetyPlusMatchActivityAttributes>.activities.first(where: { $0.attributes.matchID == match.id }) {
            await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(180)))
            activities[match.id] = activity
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = NinetyPlusMatchActivityAttributes(
            matchID: match.id,
            home: SportsArabic.team(match.home),
            away: SportsArabic.team(match.away),
            league: SportsArabic.league(match.league),
            kickoff: match.date
        )
        do {
            let activity = try Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(180)), pushType: nil)
            activities[match.id] = activity
        } catch { }
    }

    static func end(matchID: String) async {
        let targets = Activity<NinetyPlusMatchActivityAttributes>.activities.filter { $0.attributes.matchID == matchID }
        for activity in targets { await activity.end(nil, dismissalPolicy: .immediate) }
        activities[matchID] = nil
    }
}
#endif
