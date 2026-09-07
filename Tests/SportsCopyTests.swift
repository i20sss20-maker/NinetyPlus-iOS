import Foundation

@main enum SportsCopyTests {
    static func main() {
        let now = Date(timeIntervalSince1970: 1788780000)
        var checks = 0
        func check(_ result: Bool, _ message: String) { precondition(result, message); checks += 1 }
        func ago(_ seconds: Double) -> String { SportsCopy.published(now.addingTimeInterval(-seconds), now: now) }
        check(ago(0) == "الآن", "Now")
        check(ago(59) == "الآن", "No second-by-second abbreviations")
        check(ago(60) == "منذ دقيقة", "Singular minute")
        check(ago(120) == "منذ دقيقتين", "Dual minute")
        check(ago(180) == "منذ 3 دقائق", "Three minutes")
        check(ago(10 * 60) == "منذ 10 دقائق", "Ten minutes")
        check(ago(11 * 60) == "منذ 11 دقيقة", "Eleven minutes")
        check(ago(3599) == "منذ 59 دقيقة", "Do not round into a future unit")
        check(ago(3600) == "منذ ساعة", "Singular hour")
        check(ago(7200) == "منذ ساعتين", "Dual hour")
        check(ago(10800) == "منذ 3 ساعات", "Plural hour")
        check(ago(39600) == "منذ 11 ساعة", "Eleven hours")
        check(ago(86400) == "منذ يوم", "One day")
        check(ago(172800) == "منذ يومين", "Two days")
        check(ago(259200) == "منذ 3 أيام", "Three days")
        check(!ago(7 * 86400).hasPrefix("منذ"), "Older article shows full date")
        check(!ago(-3600).hasPrefix("منذ") && ago(-3600) != "الآن", "Future publication time is not silently recast as now")
        check(SportsCopy.birthDate(nil) == nil, "Missing date remains missing")
        check(SportsCopy.birthDate("") == nil, "Empty date remains missing")
        check(SportsCopy.birthDate("2025-02-30") == nil, "Invalid birthday is not repaired into March")
        check(SportsCopy.birthDate("2024-02-29") != nil, "Valid leap day")
        check(SportsCopy.birthDate("1985-02-05")?.contains("فبراير") == true, "Gregorian Arabic birthday")
        check(SportsCopy.birthDate("1985-2-5") == nil, "Unexpected input is not guessed")
        print("PASS: \(checks) Arabic copy and publication-time checks")
    }
}
