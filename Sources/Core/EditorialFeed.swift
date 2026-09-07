import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

struct RealArticle: Identifiable, Hashable, Codable {
    let id: UUID
    let title: String
    let source: String
    let date: Date
    let url: URL?
    let imageURL: URL?
    init(id: UUID = UUID(), title: String, source: String, date: Date, url: URL?, imageURL: URL? = nil) {
        self.id = id; self.title = title; self.source = source; self.date = date
        self.url = url; self.imageURL = imageURL
    }
}

enum EditorialFeedError: LocalizedError {
    case invalidFeed
    var errorDescription: String? { "تعذر قراءة موجز الأخبار." }
}

/// Reads only images explicitly associated with the same RSS item. Never inserts
/// a stock photo, a publisher icon, or an invented publication time.
final class EditorialRSSParser: NSObject, XMLParserDelegate {
    private let data: Data
    private let sourceName: String
    private var articles: [RealArticle] = []
    private var stack: [String] = []
    private var fields: [String: String] = [:]
    private var insideItem = false
    private var isRSS = false
    private var image: URL?
    private var imageWidth = -1
    init(data: Data, source: String) { self.data = data; sourceName = source }

    func parse() throws -> [RealArticle] {
        guard data.count <= 4_000_000,
              !(String(data: data, encoding: .utf8) ?? "").uppercased().contains("<!DOCTYPE") else { throw EditorialFeedError.invalidFeed }
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = self
        guard parser.parse(), isRSS else { throw EditorialFeedError.invalidFeed }
        return articles
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        let tag = name.lowercased()
        stack.append(tag)
        if tag == "rss" || tag == "rdf:rdf" { isRSS = true }
        if tag == "item" {
            insideItem = true; fields = [:]; image = nil; imageWidth = -1
        }
        guard insideItem else { return }
        let type = attributes["type"]?.lowercased() ?? ""
        if tag == "media:thumbnail" || (tag == "media:content" && (attributes["medium"] == "image" || type.hasPrefix("image/"))) || (tag == "enclosure" && type.hasPrefix("image/")) {
            if let url = Self.webURL(attributes["url"]), (Int(attributes["width"] ?? "") ?? 0) >= imageWidth {
                image = url; imageWidth = Int(attributes["width"] ?? "") ?? 0
            }
        }
    }
    func parser(_ parser: XMLParser, foundCharacters text: String) { append(text) }
    func parser(_ parser: XMLParser, foundCDATA block: Data) {
        if let text = String(data: block, encoding: .utf8) { append(text) }
    }
    private func append(_ text: String) {
        guard insideItem, let tag = stack.last,
              ["title", "source", "link", "pubdate", "dc:date", "description", "content:encoded"].contains(tag) else { return }
        fields[tag, default: ""] += text
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name.lowercased() == "item" {
            finishItem(); insideItem = false
        }
        if !stack.isEmpty { stack.removeLast() }
    }
    private func finishItem() {
        guard let url = Self.webURL(fields["link"]),
              let date = Self.publicationDate(fields["pubdate"] ?? fields["dc:date"] ?? "") else { return }
        let source = Self.clean(fields["source"] ?? sourceName)
        var title = Self.clean(fields["title"] ?? "")
        let suffix = " - " + source
        if !source.isEmpty, title.hasSuffix(suffix) { title.removeLast(suffix.count) }
        guard !title.isEmpty else { return }
        let artwork = image ?? Self.htmlImage(fields["description"] ?? "") ?? Self.htmlImage(fields["content:encoded"] ?? "")
        articles.append(RealArticle(title: title, source: source.isEmpty ? sourceName : source, date: date, url: url, imageURL: artwork))
    }
    static func webURL(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "&amp;", with: "&")),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }
    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func publicationDate(_ raw: String) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss zzz", "yyyy-MM-dd'T'HH:mm:ssZZZZZ"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return ISO8601DateFormatter().date(from: text)
    }
    private static func htmlImage(_ text: String) -> URL? {
        guard let regex = try? NSRegularExpression(pattern: #"<img\b[^>]*\bsrc\s*=\s*["']([^"']+)["']"#, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return webURL(String(text[range]))
    }
}
