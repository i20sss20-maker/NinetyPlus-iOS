import Foundation
import SwiftUI

struct LiveMatch: Identifiable, Hashable {
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

struct RealArticle: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let source: String
    let date: Date
    let url: URL?
}

@MainActor
final class SportsStore: ObservableObject {
    @Published var matches: [LiveMatch] = []
    @Published var news: [RealArticle] = []
    @Published var transfers: [RealArticle] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    static let shared = SportsStore()
    private init() {}

    func refresh() async {
        isLoading = true
        errorMessage = nil
        async let m = fetchMatches()
        async let n = fetchRSS(query: "كرة القدم السعودية OR الدوري السعودي OR الهلال OR النصر OR الاتحاد")
        async let t = fetchRSS(query: "انتقالات الدوري السعودي OR Saudi Pro League transfers")
        do {
            let result = try await (m, n, t)
            matches = result.0
            news = result.1
            transfers = result.2
        } catch {
            errorMessage = "تعذر تحديث بعض البيانات الآن"
        }
        isLoading = false
    }

    private func fetchMatches() async throws -> [LiveMatch] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        guard let url = URL(string: "https://www.thesportsdb.com/api/v1/json/123/eventsday.php?d=\(today)&s=Soccer") else { return [] }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(EventDayResponse.self, from: data)
        let events = decoded.events ?? []
        let priority = events.sorted { scorePriority($0) > scorePriority($1) }
        return priority.prefix(60).map { e in
            LiveMatch(
                id: e.idEvent ?? UUID().uuidString,
                league: e.strLeague ?? "كرة القدم",
                home: e.strHomeTeam ?? "—",
                away: e.strAwayTeam ?? "—",
                homeBadge: e.strHomeTeamBadge,
                awayBadge: e.strAwayTeamBadge,
                homeScore: e.intHomeScore,
                awayScore: e.intAwayScore,
                time: displayTime(e),
                status: e.strStatus ?? ""
            )
        }
    }

    private func scorePriority(_ e: SportsEvent) -> Int {
        let name = (e.strLeague ?? "").lowercased()
        let team = "\(e.strHomeTeam ?? "") \(e.strAwayTeam ?? "")".lowercased()
        var score = 0
        if name.contains("saudi") || name.contains("champions") || name.contains("premier") || name.contains("laliga") || name.contains("serie a") { score += 8 }
        if team.contains("hilal") || team.contains("nassr") || team.contains("ittihad") || team.contains("ahli") { score += 10 }
        if e.intHomeScore != nil || e.intAwayScore != nil { score += 3 }
        return score
    }

    private func displayTime(_ e: SportsEvent) -> String {
        if let h = e.intHomeScore, let a = e.intAwayScore { return "\(h) - \(a)" }
        if let time = e.strTime, !time.isEmpty { return String(time.prefix(5)) }
        return "اليوم"
    }

    private func fetchRSS(query: String) async throws -> [RealArticle] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://news.google.com/rss/search?q=\(encoded)&hl=ar&gl=SA&ceid=SA:ar") else { return [] }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        let parser = RSSParser(data: data)
        return Array(parser.parse().prefix(40))
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
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        element = elementName
        if elementName == "item" {
            insideItem = true
            title = ""; link = ""; pubDate = ""; source = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideItem else { return }
        switch element {
        case "title": title += string
        case "link": link += string
        case "pubDate": pubDate += string
        case "source": source += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            insideItem = false
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
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
