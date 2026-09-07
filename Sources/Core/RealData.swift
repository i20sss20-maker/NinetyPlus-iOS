import Foundation
import SwiftUI

struct RealArticle: Identifiable, Hashable, Codable {
    let id: UUID
    let title: String
    let source: String
    let date: Date
    let url: URL?
    let imageURL: URL?

    init(id: UUID = UUID(), title: String, source: String, date: Date, url: URL?, imageURL: URL? = nil) {
        self.id = id
        self.title = title
        self.source = source
        self.date = date
        self.url = url
        self.imageURL = imageURL
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
    private let cacheKey = "ninetyplus.editorial.cache.v2"

    private init() { loadCache() }

    func refreshIfStale(maxAge: TimeInterval) async {
        if let lastUpdated, !news.isEmpty || !transfers.isEmpty,
           Date().timeIntervalSince(lastUpdated) >= 0,
           Date().timeIntervalSince(lastUpdated) < maxAge { return }
        await refresh()
    }

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
                ? "تعذر الوصول إلى مصادر الأخبار الآن."
                : "تعذر تحديث بعض المصادر؛ يتم عرض آخر أخبار تم استلامها."
        }
    }

    private func fetchRSS(query: String) async throws -> [RealArticle] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://news.google.com/rss/search?q=\(encoded)&hl=ar&gl=SA&ceid=SA:ar") else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("NinetyPlus/2.0 iOS", forHTTPHeaderField: "User-Agent")
        request.setValue("application/rss+xml, application/xml, text/xml", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return Array(RSSParser(data: data).parse().prefix(60))
    }

    private func dedupe(_ input: [RealArticle]) -> [RealArticle] {
        var seen = Set<String>()
        return input.filter {
            let key = $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, let url = $0.url,
                  ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return false }
            return seen.insert(key).inserted
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

private final class RSSParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var items: [RealArticle] = []
    private var element = ""
    private var title = ""
    private var link = ""
    private var pubDate = ""
    private var source = ""
    private var descriptionHTML = ""
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
            descriptionHTML = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideItem else { return }
        switch element {
        case "title": title += string
        case "link": link += string
        case "pubDate": pubDate += string
        case "source": source += string
        case "description": descriptionHTML += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            insideItem = false
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedLink = link.trimmingCharacters(in: .whitespacesAndNewlines)
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            items.append(
                RealArticle(
                    title: trimmedTitle,
                    source: source.trimmingCharacters(in: .whitespacesAndNewlines),
                    date: df.date(from: pubDate) ?? Date(),
                    url: URL(string: trimmedLink),
                    imageURL: extractImageURL(from: descriptionHTML)
                )
            )
        }
        element = ""
    }

    private func extractImageURL(from html: String) -> URL? {
        let patterns = [
            #"<img[^>]+src=[\"']([^\"']+)[\"']"#,
            #"https?://[^\s\"'<>]+\.(?:jpg|jpeg|png|webp)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            guard let match = regex.firstMatch(in: html, range: range) else { continue }
            let capture = match.numberOfRanges > 1 ? match.range(at: 1) : match.range(at: 0)
            guard let swiftRange = Range(capture, in: html) else { continue }
            let raw = String(html[swiftRange])
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&#39;", with: "'")
                .replacingOccurrences(of: "&quot;", with: "\"")
            if let url = URL(string: raw), ["https", "http"].contains(url.scheme?.lowercased() ?? "") { return url }
        }
        return nil
    }
}

struct RemoteBadge: View {
    let url: String?

    private var imageURL: URL? {
        guard let raw = url?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, let parsed = URL(string: raw),
              ["https", "http"].contains(parsed.scheme?.lowercased() ?? "") else { return nil }
        return parsed
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.055))
            if let imageURL {
                AsyncImage(url: imageURL, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().tint(AppTheme.green).scaleEffect(0.7)
                    case .success(let image):
                        image.resizable().scaledToFit().padding(4)
                    case .failure:
                        fallback
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.border, lineWidth: 1))
        .clipped()
    }

    private var fallback: some View {
        Image(systemName: "sportscourt.fill")
            .resizable()
            .scaledToFit()
            .padding(12)
            .foregroundStyle(AppTheme.dimmed)
    }
}

struct EditorialArtwork: View {
    let article: RealArticle

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [AppTheme.cardRaised, AppTheme.greenDeep.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let url = article.imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default:
                        Image(systemName: "newspaper.fill").font(.title2).foregroundStyle(AppTheme.green)
                    }
                }
            } else {
                Image(systemName: "newspaper.fill").font(.title2).foregroundStyle(AppTheme.green)
            }
        }
        .clipped()
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.border, lineWidth: 1))
    }
}
