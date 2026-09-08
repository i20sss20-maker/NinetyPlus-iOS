import SwiftUI
import UserNotifications

struct V2FeaturePreferences {
    static let oledBlack = "v2.oledBlack"
    static let compactMatches = "v2.compactMatches"
    static let haptics = "v2.haptics"
    static let spoilerMode = "v2.spoilerMode"
    static let lowDataMode = "v2.lowDataMode"
    static let liveOnly = "v2.liveOnly"
    static let followedOnly = "v2.followedOnly"
    static let pinnedOnly = "v2.pinnedOnly"
    static let reminderLeadMinutes = "v2.reminderLeadMinutes"
    static let notifyGoals = "v2.notifyGoals"
    static let notifyKickoff = "v2.notifyKickoff"
    static let notifyLineups = "v2.notifyLineups"
    static let notifyRedCards = "v2.notifyRedCards"
}

enum V2Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard UserDefaults.standard.object(forKey: V2FeaturePreferences.haptics) as? Bool ?? true else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func success() {
        guard UserDefaults.standard.object(forKey: V2FeaturePreferences.haptics) as? Bool ?? true else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

enum PinnedMatchStore {
    private static let key = "v2.pinnedMatchIDs"

    static var ids: Set<String> {
        Set((UserDefaults.standard.string(forKey: key) ?? "")
            .split(separator: ",")
            .map(String.init)
            .filter { !$0.isEmpty })
    }

    static func contains(_ id: String) -> Bool { ids.contains(id) }

    @discardableResult
    static func toggle(_ id: String) -> Bool {
        var value = ids
        let nowPinned: Bool
        if value.contains(id) {
            value.remove(id)
            nowPinned = false
        } else {
            value.insert(id)
            nowPinned = true
        }
        UserDefaults.standard.set(value.sorted().joined(separator: ","), forKey: key)
        V2Haptics.impact(nowPinned ? .medium : .light)
        return nowPinned
    }
}

enum MatchReminderScheduler {
    static func schedule(match: APIPlusMatch, leadMinutes: Int) async throws {
        guard let kickoff = match.date else { return }
        let fireDate = kickoff.addingTimeInterval(TimeInterval(-max(0, leadMinutes) * 60))
        guard fireDate > Date() else { return }

        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "مباراة بعد \(leadMinutes) دقيقة".englishDigits
        content.body = "\(SportsArabic.team(match.home)) ضد \(SportsArabic.team(match.away))".englishDigits
        content.sound = .default
        content.userInfo = ["matchID": match.id]

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: "ninetyplus.reminder.\(match.id)", content: content, trigger: trigger)
        try await center.add(request)
    }

    static func cancel(matchID: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["ninetyplus.reminder.\(matchID)"])
    }
}
