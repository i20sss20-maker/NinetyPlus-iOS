import Foundation

/// Central refresh policy for live-score surfaces.
///
/// The app should feel live without exhausting a limited upstream provider quota.
/// A single fixtures request covers all matches for the current day, so we refresh
/// more often only while at least one match is actually live.
enum AppRefreshPolicy {
    /// Minimum age before an ordinary foreground refresh may hit the backend again.
    static let todayFreshness: TimeInterval = 90

    /// In-memory cache TTL for the current fixture day.
    static let todayCacheTTL: TimeInterval = 90

    /// Live matches still update frequently, but not every minute indefinitely.
    static let liveMatchInterval: TimeInterval = 120

    /// When nothing is live, five-minute refreshes are enough for schedule changes.
    static let idleMatchInterval: TimeInterval = 300

    static func matchInterval(hasLiveMatches: Bool) -> TimeInterval {
        hasLiveMatches ? liveMatchInterval : idleMatchInterval
    }
}

// EditorialStore owns its per-source freshness policy.
