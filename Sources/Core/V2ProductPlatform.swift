import Foundation
import SwiftUI
import UserNotifications
import EventKit

enum V2PreferenceKey {
    static let spoilerMode = "v2.spoilerMode"
    static let lowDataMode = "v2.lowDataMode"
    static let haptics = "v2.haptics"
    static let notifyKickoff = "v2.notifyKickoff"
    static let notifyGoals = "v2.notifyGoals"
    static let notifyLineups = "v2.notifyLineups"
    static let notifyRedCards = "v2.notifyRedCards"
    static let notifyTransfers = "v2.notifyTransfers"
    static let favoriteHomeMode = "v2.favoriteHomeMode"
}

enum V2FeatureAvailability: String, CaseIterable {
    case liveActivities, widgets, notifications, deepLinks, calendar, shareCards
    case momentum, shotMap, heatMap, passingMap, defensiveMap, expectedGoals, injuries, contracts, broadcastGuide

    var requiresProviderData: Bool {
        switch self {
        case .momentum, .shotMap, .heatMap, .passingMap, .defensiveMap, .expectedGoals, .injuries, .contracts, .broadcastGuide: return true
        default: return false
        }
    }
}

@MainActor
enum V2Permissions {
    static func requestNotifications() async -> Bool {
        do { return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) }
        catch { return false }
    }

    static func requestCalendarAccess() async -> Bool {
        let store = EKEventStore()
        if #available(iOS 17.0, *) {
            return (try? await store.requestWriteOnlyAccessToEvents()) ?? false
        }
        return false
    }
}

enum V2DeepLink {
    static let scheme = "ninetyplus"
    static func match(_ id: String) -> URL? { URL(string: "\(scheme)://match/\(id)") }
    static func team(_ id: String) -> URL? { URL(string: "\(scheme)://team/\(id)") }
    static func player(_ id: String) -> URL? { URL(string: "\(scheme)://player/\(id)") }
    static func league(_ id: String) -> URL? { URL(string: "\(scheme)://league/\(id)") }
}
