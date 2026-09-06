import Foundation
import SwiftUI

struct LiveMatch: Identifiable, Hashable, Codable {
    let id: String
    let league: String
    let home: String
    let away: String
    let homeBadge: String?
    let awayBadge: String?
    let homeScore: String?
    let awayScore: String?
    let time: String
    let status: String
}

struct RealArticle: Identifiable, Hashable, Codable {
    let id: UUID
    let title: String
    let source: String
    let date: Date
    let url: URL?

    init(id: UUID = UUID(), title: String, source: String, date: Date, url: URL?) {
        self.id = id; self.title = title; self.source = source; self.date = date; self.url = url
    }
}

private struct SportsCache: Codable {
    let matches: [LiveMatch]
    let news: [RealArticle]
    let transfers: [RealArticle]
    let savedAt: Date
}

@MainActor
final class SportsStore: ObservableObject {
    @Published var matches: [LiveMatch] = []
    @Published var news: [RealArticle] = []
    @Published var transfers: [RealArticle] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?

    static let shared = SportsStore()
    private let cacheKey = "ninetyplus.sports.cache.v2"
    private init() { loadCache() }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        async let m = fetchMatches(date: Date())
        async let n = fetchRSS(query: "كرة القدم السعودية OR دوري روشن OR الهلال OR النصر OR الاتحاد OR الأهلي")
        async let t = fetchRSS(query: "انتقالات الدوري السعودي OR Saudi Pro League transfers OR football transfers")
        let result = await (try? m, try? n, try? t)

        var changed = false
        if let newMatches = result.0 { matches = newMatches; changed = true }
        if let newNews = result.1, !newNews.isEmpty { news = dedupe(newNews); changed = true }
        if let newTransfers = result.2, !newTransfers.isEmpty { transfers = dedupe(newTransfers); changed = true }

        if changed {
            lastUpdated = Date()
            saveCache()
        } else {
            errorMessage = matches.isEmpty && news.isEmpty ? "تعذر الاتصال بمصادر البيانات الآن" : "تعذر تحديث بعض المصادر، يتم عرض آخر بيانات محفوظة"
        }
        isLoading = false
    }

    func matches(on date: Date) async throws -> [LiveMatch] {
        try await fetchMatches(date: date)
    }

    private func fetchMatches(date: Date) async throws -> [LiveMatch] {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: date)
        guard let url = URL(string: "https://www.thesportsdb.com/api/v1/json/123/eventsday.php?d=\(day)&s=Soccer") else { return [] }
        var request = URLRequest(url: url); request.timeoutInterval = 15; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("NinetyPlus/1.1 iOS", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(EventDayResponse.self, from: data)
        let events = decoded.events ?? []
        let priority = events.sorted { scorePriority($0) > scorePriority($1) }
        return priority.prefix(100).map { e in
            LiveMatch(
                id: e.idEvent ?? UUID().uuidString,
                league: e.strLeague ?? "كرة القدم",
                home: e.strHomeTeam ?? "—",
                away: e.strAwayTeam ?? "—",
                homeBadge: e.strHomeTeamBadge,
                awayBadge: e.strAwayTeamBadge,
                homeScore: normalizedScore(e.intHomeScore),
                awayScore: normalizedScore(e.intAwayScore),
                time: displayTime(e),
                status: e.strStatus ?? ""
            )
        }
    }

    private func normalizedScore(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.lowercased() != "null" else { return nil }
        return value
    }

    private func scorePriority(_ e: SportsEvent) -> Int {
        let name = (e.strLeague ?? "").lowercased()
        let team = "\(e.strHomeTeam ?? "") \(e.strAwayTeam ?? "")".lowercased()
        var score = 0
        if name.contains("saudi") || name.contains("champions") || name.contains("premier") || name.contains("laliga") || name.contains("serie a") || name.contains("bundesliga") { score += 8 }
        if team.contains("hilal") || team.contains("nassr") || team.contains("ittihad") || team.contains("ahli") { score += 10 }
        if e.intHomeScore != nil || e.intAwayScore != nil { score += 3 }
        return score
    }

    private func displayTime(_ e: SportsEvent) -> String {
        if let time = e.strTime, !time.isEmpty { return String(time.prefix(5)) }
        return "—"
    }

    private func fetchRSS(query: String) async throws -> [RealArticle] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://news.google.com/rss/search?q=\(encoded)&hl=ar&gl=SA&ceid=SA:ar") else { return [] }
        var request = URLRequest(url: url); request.timeoutInterval = 15; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("NinetyPlus/1.1 iOS", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return Array(RSSParser(data: data).parse().prefix(50))
    }

    private func dedupe(_ input: [RealArticle]) -> [RealArticle] {
        var seen = Set<String>()
        return input.filter {
            let key = $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !key.isEmpty && seen.insert(key).inserted
        }
    }

    private func saveCache() {
        let cache = SportsCache(matches: matches, news: news, transfers: transfers, savedAt: lastUpdated ?? Date())
        if let data = try? JSONEncoder().encode(cache) { UserDefaults.standard.set(data, forKey: cacheKey) }
    }

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey), let cache = try? JSONDecoder().decode(SportsCache.self, from: data) else { return }
        matches = cache.matches; news = cache.news; transfers = cache.transfers; lastUpdated = cache.savedAt
    }
}

private struct EventDayResponse: Decodable { let events: [SportsEvent]? }
private struct SportsEvent: Decodable {
    let idEvent: String?
    let strLeague: String?
    let strHomeTeam: String?
    let strAwayTeam: String?
    let strHomeTeamBadge: String?
    let strAwayTeamBadge: String?
    let intHomeScore: String?
    let intAwayScore: String?
    let strTime: String?
    let strStatus: String?
}

private final class RSSParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var items: [RealArticle] = []
    private var element = ""
    private var title = ""
    private var link = ""
    private var pubDate = ""
    private var source = ""
    private var insideItem = false

    init(data: Data) { self.data = data }

    func parse() -> [RealArticle] {
        let parser = XMLParser(data: data); parser.delegate = self; parser.parse(); return items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        element = elementName
        if elementName == "item" { insideItem = true; title = ""; link = ""; pubDate = ""; source = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideItem else { return }
        switch element { case "title": title += string; case "link": link += string; case "pubDate": pubDate += string; case "source": source += string; default: break }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            insideItem = false
            let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            items.append(RealArticle(title: title.trimmingCharacters(in: .whitespacesAndNewlines), source: source.trimmingCharacters(in: .whitespacesAndNewlines), date: df.date(from: pubDate) ?? Date(), url: URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines))))
        }
        element = ""
    }
}

struct RemoteBadge: View {
    let url: String?
    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFit()
            default: Image(systemName: "shield.fill").resizable().scaledToFit().foregroundStyle(AppTheme.green.opacity(0.7))
            }
        }
    }
}
