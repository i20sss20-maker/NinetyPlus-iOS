import Foundation
import UserNotifications

@main struct MatchReminderScheduleTests {
    static func main() {
        let now = Date()
        let kickoff = Date(timeIntervalSince1970: floor(now.addingTimeInterval(86400).timeIntervalSince1970))
        for minutes in [5, 15, 30, 60] {
            let parts = MatchReminderSchedule.components(kickoff: kickoff, minutesBefore: minutes, now: now)!
            let expected = kickoff.addingTimeInterval(Double(-minutes * 60))
            precondition(parts.timeZone == TimeZone(secondsFromGMT: 0))
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            precondition(trigger.nextTriggerDate() == expected, "Notification must fire at the same absolute instant")
            for zone in ["Asia/Riyadh", "America/Los_Angeles", "Asia/Kolkata", "Pacific/Auckland"] {
                var deviceCalendar = Calendar(identifier: .gregorian)
                deviceCalendar.timeZone = TimeZone(identifier: zone)!
                precondition(deviceCalendar.date(from: parts) == expected, "Device timezone must not shift reminder")
            }
        }
        precondition(MatchReminderSchedule.components(kickoff: kickoff, minutesBefore: 10, now: now) == nil)
        precondition(MatchReminderSchedule.components(kickoff: kickoff, minutesBefore: 30, now: kickoff) == nil,
                     "Permission granted after reminder time must not schedule a stale reminder")
        let near = now.addingTimeInterval(30 * 60 + 5)
        precondition(MatchReminderSchedule.components(kickoff: near, minutesBefore: 30, now: now) == nil)
        print("Reminder scheduling: all lead times, device timezones, real notification trigger and expiry passed")
    }
}
