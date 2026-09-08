import Foundation
import UserNotifications

@MainActor final class MatchReminderCenter: ObservableObject {
    static let shared = MatchReminderCenter()
    @Published private(set) var message: String?
    @Published private(set) var scheduledIDs: Set<String> = []
    private let center = UNUserNotificationCenter.current()

    private init() { Task { await reload() } }

    func identifier(matchID: String, minutes: Int) -> String { "ninetyplus.match.\(matchID).\(minutes)" }
    func isScheduled(matchID: String, minutes: Int) -> Bool { scheduledIDs.contains(identifier(matchID: matchID, minutes: minutes)) }

    func schedule(match: APIPlusMatch, minutesBefore: Int) async {
        guard let kickoff = match.date, FixturePhase.isUpcoming(match.status), [5, 15, 30, 60].contains(minutesBefore) else {
            message = "لا يمكن إنشاء التذكير لهذه المباراة."
            return
        }
        let fire = kickoff.addingTimeInterval(TimeInterval(-minutesBefore * 60))
        guard fire > Date().addingTimeInterval(5) else {
            message = "موعد هذا التذكير مضى أو أصبح قريبًا جدًا."
            return
        }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { message = "التنبيهات غير مسموحة لهذا التطبيق من إعدادات iOS."; return }
            var calendar = SportsDisplayDate.calendar
            calendar.timeZone = SportsDisplayDate.calendar.timeZone
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let content = UNMutableNotificationContent()
            content.title = "مباراة بعد \(minutesBefore) دقيقة"
            content.body = "\(SportsArabic.team(match.home)) × \(SportsArabic.team(match.away))"
            content.sound = .default
            content.userInfo = ["matchID": match.id]
            let request = UNNotificationRequest(identifier: identifier(matchID: match.id, minutes: minutesBefore), content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            try await center.add(request)
            message = "تم ضبط التذكير قبل \(minutesBefore) دقيقة."
            await reload()
        } catch { message = "تعذر إنشاء التذكير: \(error.localizedDescription)" }
    }

    func cancel(matchID: String, minutes: Int) async {
        let id = identifier(matchID: matchID, minutes: minutes)
        center.removePendingNotificationRequests(withIdentifiers: [id])
        message = "تم إلغاء التذكير."
        await reload()
    }

    func reload() async {
        let requests = await center.pendingNotificationRequests()
        scheduledIDs = Set(requests.map(\.identifier).filter { $0.hasPrefix("ninetyplus.match.") })
    }
}
