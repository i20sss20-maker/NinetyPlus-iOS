import Foundation
#if canImport(ActivityKit)
import ActivityKit

struct NinetyPlusMatchActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var homeScore: Int?
        var awayScore: Int?
        var status: String
        var elapsed: Int?
        var updatedAt: Date
    }

    var matchID: String
    var home: String
    var away: String
    var league: String
    var kickoff: Date?
}
#endif
