import Foundation

enum MatchReminderSchedule {
    /// Preserve the match's absolute instant regardless of the device timezone
    /// or a timezone change between scheduling and delivery.
    static func components(kickoff: Date, minutesBefore: Int, now: Date = Date()) -> DateComponents? {
        guard [5, 15, 30, 60].contains(minutesBefore) else { return nil }
        let fire = kickoff.addingTimeInterval(TimeInterval(-minutesBefore * 60))
        guard fire > now.addingTimeInterval(5) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return components
    }
}
