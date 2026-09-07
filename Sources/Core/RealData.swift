import Foundation
import SwiftUI

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

private struct EditorialCache: Codable {
    let news: [RealArticle]
    let transfers: [RealArticle]
    let savedAt: Date
}

@MainActor
final class EditorialStore: ObservableObject {
    @Published var news: [RealArticle] = []
    @Published var transfers: [RealArticle] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?

    static let shared = EditorialStore()
    private let cacheKey = "ninetyplus.editorial.cache.v1"

    private init() { loadCache() }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let n = fetchRSS(query: "كرة القدم السعودية OR دوري روشن OR الهلال OR النصر OR الاتحاد OR الأهلي")
        async let t = fetchRSS(query: "انتقالات الدوري السعودي OR Saudi Pro League transfers OR football transfers")
        let result = await (try? n, try? t)

        var changed = false
        if let newNews = result.0, !newNews.isEmpty {
            news = dedupe(newNews)
            changed = true
        }
        if let newTransfers = result.1, !newTransfers.isEmpty {
            transfers = dedupe(newTransfers)
            changed = true
        }

        if changed {
            lastUpdated = Date()
            saveCache()
        } else {
            errorMessage = news.isEmpty && transfers.isEmpty
                ? "تعذر الاتصال بمصادر الأخبار الآن"
                : "تعذر تحديث بعض المصادر، يتم عرض آخر بيانات محفوظة"
        }
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
            return !key.isEmpty && $0.url != nil && seen.insert(key).inserted
        }
        .sorted { $0.date > $1.date }
    }

    private func saveCache() {
        let cache = EditorialCache(news: news, transfers: transfers, savedAt: lastUpdated ?? Date())
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cache = try? JSONDecoder().decode(EditorialCache.self, from: data) else { return }
        news = cache.news
        transfers = cache.transfers
        lastUpdated = cache.savedAt
    }
}

// Temporary source compatibility while legacy view names are being removed.
typealias SportsStore = EditorialStore

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
            case .success(let image): image.resizable().scaledToFit()
            default:
                Image(systemName: "shield.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(AppTheme.green.opacity(0.7))
            }
        }
    }
}
