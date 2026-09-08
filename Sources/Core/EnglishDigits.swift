import Foundation

enum EnglishDigits {
    private static let map: [Character: Character] = [
        "٠":"0","١":"1","٢":"2","٣":"3","٤":"4","٥":"5","٦":"6","٧":"7","٨":"8","٩":"9",
        "۰":"0","۱":"1","۲":"2","۳":"3","۴":"4","۵":"5","۶":"6","۷":"7","۸":"8","۹":"9"
    ]
    static func convert(_ value: String) -> String { String(value.map { map[$0] ?? $0 }) }
    static func integer(_ value: Int?) -> String { value.map(String.init) ?? "—" }
    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.0f%%", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

extension String {
    var englishDigits: String { EnglishDigits.convert(self) }
}
