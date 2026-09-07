import Foundation

/// Arabic labels avoid the abbreviated, second-by-second duration produced by
/// Text(date, style: .relative), and keep unknown source values visibly unknown.
enum SportsCopy {
    static func metric(_ value: Int?) -> String {
        guard let value, value >= 0 else { return "—" }
        return String(value)
    }

    static func published(_ date: Date, now: Date = Date()) -> String {
        let elapsed = now.timeIntervalSince(date)
        guard elapsed.isFinite, elapsed >= -60 else { return absolute(date) }
        if elapsed < 60 { return "الآن" }
        if elapsed < 3600 {
            let count = Int(elapsed / 60)
            return ago(count, one: "دقيقة", two: "دقيقتين", plural: "دقائق")
        }
        if elapsed < 86400 {
            let count = Int(elapsed / 3600)
            return ago(count, one: "ساعة", two: "ساعتين", plural: "ساعات")
        }
        if elapsed < 7 * 86400 {
            let count = Int(elapsed / 86400)
            return ago(count, one: "يوم", two: "يومين", plural: "أيام")
        }
        return absolute(date)
    }

    private static func ago(_ count: Int, one: String, two: String, plural: String) -> String {
        if count == 1 { return "منذ \(one)" }
        if count == 2 { return "منذ \(two)" }
        return "منذ \(count) \((3...10).contains(count) ? plural : one)"
    }

    static func birthDate(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.calendar = Calendar(identifier: .gregorian)
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"
        parser.isLenient = false
        guard let date = parser.date(from: text), parser.string(from: date) == text else { return nil }
        return absolute(date, includeTime: false)
    }

    private static func absolute(_ date: Date, includeTime: Bool = true) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ar_SA@calendar=gregorian")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Riyadh")
        formatter.dateFormat = includeTime ? "d MMMM yyyy، HH:mm" : "d MMMM yyyy"
        return formatter.string(from: date)
    }
}
