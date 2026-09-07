import Foundation
import SwiftUI
import UserNotifications

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
        self.id = id
        self.title = title
        self.source = source
        self.date = date
        self.url = url
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
    @Published var liveAlert: String?

    static let shared = SportsStore()
    private let cacheKey = "ninetyplus.sports.cache.v3"

    private init() {
        loadCache()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        async let m = fetchMatches(date: Date())
        async let n = fetchRSS(query: "كرة القدم السعودية OR دوري روشن OR الهلال OR النصر OR الاتحاد OR الأهلي")
        async let t = fetchRSS(query: "انتقالات الدوري السعودي OR Saudi Pro League transfers OR football transfers")
        let result = await (try? m, try? n, try? t)

        var changed = false
        if let newMatches = result.0 {
            detectFollowedMatchChanges(old: matches, new: newMatches)
            matches = newMatches
            changed = true
        }
        if let newNews = result.1, !newNews.isEmpty {
            news = dedupe(newNews)
            changed = true
        }
        if let newTransfers = result.2, !newTransfers.isEmpty {
            transfers = dedupe(newTransfers)
            changed = true
        }

        if changed {
            lastUpdated = Date()
            saveCache()
        } else {
            errorMessage = matches.isEmpty && news.isEmpty
                ? "تعذر الاتصال بمصادر البيانات الآن"
                : "تعذر تحديث بعض المصادر، يتم عرض آخر بيانات محفوظة"
        }
        isLoading = false
    }

    func matches(on date: Date) async throws -> [LiveMatch] {
        let fresh = try await fetchMatches(date: date)
        if Calendar.current.isDateInToday(date) {
            detectFollowedMatchChanges(old: matches, new: fresh)
        }
        return fresh
    }

    func clearLiveAlert() {
        liveAlert = nil
    }

    private func detectFollowedMatchChanges(old: [LiveMatch], new: [LiveMatch]) {
        let followed = Set(UserDefaults.standard.string(forKey: "followedMatchIDs")?.split(separator: ",").map(String.init) ?? [])
        guard !followed.isEmpty, !old.isEmpty else { return }
        let oldMap = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })

        for match in new where followed.contains(match.id) {
            guard let previous = oldMap[match.id] else { continue }
            let before = "\(previous.homeScore ?? "-"):\(previous.awayScore ?? "-")"
            let after = "\(match.homeScore ?? "-"):\(match.awayScore ?? "-")"

            if before != after, match.homeScore != nil, match.awayScore != nil {
                let text = "⚽️ \(match.home) \(match.homeScore ?? "-") - \(match.awayScore ?? "-") \(match.away)"
                liveAlert = text
                sendLocalMatchNotification(title: "هدف أو تغير في النتيجة", body: text, matchID: match.id)
                return
            }

            let oldStatus = previous.status.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let newStatus = match.status.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard oldStatus != newStatus else { continue }

            if isKickoffStatus(oldStatus: oldStatus, newStatus: newStatus) {
                let text = "بدأت: \(match.home) ضد \(match.away)"
                liveAlert = text
                sendLocalMatchNotification(title: "بداية المباراة", body: text, matchID: match.id)
                return
            }

            if ["FT", "AET", "PEN"].contains(newStatus) {
                let text = "انتهت: \(match.home) \(match.homeScore ?? "-") - \(match.awayScore ?? "-") \(match.away)"
                liveAlert = text
                sendLocalMatchNotification(title: "نهاية المباراة", body: text, matchID: match.id)
                return
            }
        }
    }

    private func isKickoffStatus(oldStatus: String, newStatus: String) -> Bool {
        let wasPending = oldStatus.isEmpty || ["NS", "TBD", "PST"].contains(oldStatus)
        return wasPending && APISportsStore.shared.isLive(newStatus)
    }

    private func sendLocalMatchNotification(title: String, body: String, matchID: String) {
        guard UserDefaults.standard.bool(forKey: "notificationsEnabled") else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["matchID": matchID]
        let request = UNNotificationRequest(
            identifier: "ninetyplus.match.\(matchID).\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func fetchMatches(date: Date) async throws -> [LiveMatch] {
        guard APIFootballClient.isConfigured else { throw APIFootballError.missingConfiguration }
        let fixtures = try await APISportsStore.shared.fixtures(date: date)
        return fixtures.map { match in
            LiveMatch(
                id: match.id,
                league: match.league,
                home: match.home,
                away: match.away,
                homeBadge: match.homeLogo,
                awayBadge: match.awayLogo,
                homeScore: match.homeScore.map(String.init),
                awayScore: match.awayScore.map(String.init),
                time: displayTime(match.date),
                status: match.status
            )
        }
    }

    private func displayTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func fetchRSS(query: String) async throws -> [RealArticle] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://news.google.com/rss/search?q=\(encoded)&hl=ar&gl=SA&ceid=SA:ar") else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("NinetyPlus/2.0 iOS", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
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
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cache = try? JSONDecoder().decode(SportsCache.self, from: data) else { return }
        matches = cache.matches
        news = cache.news
        transfers = cache.transfers
        lastUpdated = cache.savedAt
    }
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

    init(data: Data) {
        self.data = data
    }

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
            title = ""
            link = ""
            pubDate = ""
            source = ""
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
            items.append(
                RealArticle(
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    source: source.trimmingCharacters(in: .whitespacesAndNewlines),
                    date: df.date(from: pubDate) ?? Date(),
                    url: URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines))
                )
            )
        }
        element = ""
    }
}

struct RemoteBadge: View {
    let url: String?

    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            default:
                Image(systemName: "shield.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(AppTheme.green.opacity(0.7))
            }
        }
    }
}
