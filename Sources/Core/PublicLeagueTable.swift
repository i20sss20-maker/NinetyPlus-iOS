import Foundation

/// Public-source identifiers remain in their own namespace; they must never be
/// passed to the API-Football team or match endpoints.
struct PublicLeagueTable: Decodable {
    struct Season: Decodable { let year: Int; let startDate: String?; let endDate: String?; let displayName: String? }
    struct Group: Decodable {
        struct Standings: Decodable { let entries: [Entry]; let season: Int? }
        let name: String?
        let standings: Standings
    }
    struct Entry: Decodable, Identifiable {
        struct Team: Decodable {
            struct Logo: Decodable { let href: String }
            struct Link: Decodable { let href: String; let rel: [String]? }
            let id: String
            let displayName: String
            let logos: [Logo]?
            let links: [Link]?
        }
        struct Statistic: Decodable { let name: String; let value: Double?; let displayValue: String? }
        let team: Team
        let stats: [Statistic]
        var id: String { "espn:" + team.id }
        func display(_ key: String) -> String {
            guard let value = stats.first(where: { $0.name == key }) else { return "—" }
            if let text = value.displayValue, !text.isEmpty { return text }
            guard let number = value.value, number.isFinite else { return "—" }
            return number.rounded() == number ? String(Int(number)) : String(number)
        }
        var imageURL: String? { team.logos?.first?.href }
        var sourceURL: URL? {
            guard let raw = team.links?.first(where: { $0.rel?.contains("clubhouse") == true })?.href,
                  let url = URL(string: raw), url.scheme == "https",
                  url.host == "www.espn.com" || url.host == "global.espn.com" else { return nil }
            return url
        }
    }
    let name: String
    let season: Season
    let children: [Group]

    static func decodeCurrent(_ data: Data, now: Date = Date()) throws -> PublicLeagueTable {
        let table = try JSONDecoder().decode(PublicLeagueTable.self, from: data)
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        func parse(_ text: String?) -> Date? {
            guard let text else { return nil }
            if let value = parser.date(from: text) { return value }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mmX"
            return formatter.date(from: text)
        }
        guard let start = parse(table.season.startDate), let end = parse(table.season.endDate),
              start <= now, now < end else { throw PublicTableError.outdatedSeason }
        for group in table.children {
            if let year = group.standings.season, year != table.season.year { throw PublicTableError.outdatedSeason }
            let ids = group.standings.entries.map(\.id)
            guard Set(ids).count == ids.count else { throw PublicTableError.invalidResponse }
        }
        return table
    }
}

enum PublicTableError: LocalizedError {
    case outdatedSeason, invalidResponse, unavailable
    var errorDescription: String? {
        switch self {
        case .outdatedSeason: return "المصدر لم ينشر جدول الموسم الحالي بعد. لن نعرض ترتيب موسم سابق على أنه الحالي."
        case .invalidResponse: return "تعذر قراءة جدول الترتيب."
        case .unavailable: return "تعذر الاتصال بمصدر الترتيب الآن."
        }
    }
}

enum PublicLeagueSource {
    static func code(for leagueID: String) -> String? {
        ["307": "ksa.1", "39": "eng.1", "140": "esp.1", "78": "ger.1", "135": "ita.1", "61": "fra.1"][leagueID]
    }
}

enum SportsDisplayDate {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Riyadh")!
        return calendar
    }
    static let locale = Locale(identifier: "ar_SA@calendar=gregorian")
    static func label(_ date: Date, pattern: String = "EEEE، d MMMM") -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
