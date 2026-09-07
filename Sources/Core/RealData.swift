import Foundation
import SwiftUI
import UIKit
import ImageIO

private struct EditorialFeedSnapshot: Codable {
    let articles: [RealArticle]
    let fetchedAt: Date
}
private struct EditorialFeedDefinition: Sendable {
    let id: String
    let url: URL
    let source: String
    let transfers: Bool
}

@MainActor
final class EditorialStore: ObservableObject {
    static let shared = EditorialStore()
    @Published private(set) var news: [RealArticle] = []
    @Published private(set) var transfers: [RealArticle] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var newsError: String?
    @Published private(set) var lastUpdated: Date?
    private var snapshots: [String: EditorialFeedSnapshot] = [:]
    private var failures: [String: String] = [:]
    private let cacheKey = "ninetyplus.editorial.cache.v3"
    private init() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode([String: EditorialFeedSnapshot].self, from: data) { snapshots = cached }
        assemble()
    }
    private static var feeds: [EditorialFeedDefinition] {
        func google(_ query: String) -> URL {
            var url = URLComponents(string: "https://news.google.com/rss/search")!
            url.queryItems = [.init(name: "q", value: query), .init(name: "hl", value: "ar"), .init(name: "gl", value: "SA"), .init(name: "ceid", value: "SA:ar")]
            return url.url!
        }
        return [
            .init(id: "saudi", url: google("\"دوري روشن\" OR \"الدوري السعودي\" OR \"الهلال السعودي\" OR \"النصر السعودي\" OR \"الاتحاد السعودي\""), source: "أخبار كرة القدم", transfers: false),
            .init(id: "arab-football", url: URL(string: "https://www.filgoal.com/section/9/rss/الوطن-العربي")!, source: "في الجول", transfers: false),
            .init(id: "transfers", url: google("انتقالات كرة القدم OR صفقات الدوري السعودي"), source: "أخبار الانتقالات", transfers: true)
        ]
    }
    func refreshIfStale(maxAge: TimeInterval = 90) async {
        let now = Date()
        let fresh = Self.feeds.allSatisfy { feed in
            guard failures[feed.id] == nil, let date = snapshots[feed.id]?.fetchedAt else { return false }
            return (0..<maxAge).contains(now.timeIntervalSince(date))
        }
        if !fresh { await refresh() }
    }
    func refresh() async {
        guard !isLoading, !Task.isCancelled else { return }
        isLoading = true
        defer { isLoading = false }
        await withTaskGroup(of: (String, [RealArticle]?, String?).self) { group in
            for feed in Self.feeds {
                group.addTask {
                    do { return (feed.id, try await Self.fetch(feed), nil) }
                    catch { return (feed.id, nil, "تعذر تحديث \(feed.source).") }
                }
            }
            for await (id, items, message) in group {
                guard !Task.isCancelled else { continue }
                if let items { snapshots[id] = .init(articles: items, fetchedAt: Date()); failures[id] = nil }
                else { failures[id] = message }
                assemble()
            }
        }
        if let data = try? JSONEncoder().encode(snapshots) { UserDefaults.standard.set(data, forKey: cacheKey) }
    }
    nonisolated private static func fetch(_ feed: EditorialFeedDefinition) async throws -> [RealArticle] {
        var request = URLRequest(url: feed.url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("NinetyPlus/2.0 RSS Reader", forHTTPHeaderField: "User-Agent")
        request.setValue("application/rss+xml, application/xml, text/xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        let articles = try EditorialRSSParser(data: data, source: feed.source).parse()
        return Array(articles.prefix(60))
    }
    private func assemble() {
        var existingIDs: [URL: UUID] = [:]
        for article in news + transfers { if let url = article.url { existingIDs[url] = article.id } }
        func combine(_ isTransfers: Bool) -> [RealArticle] {
            var candidates: [RealArticle] = []
            for feed in Self.feeds where feed.transfers == isTransfers {
                if let snapshot = snapshots[feed.id] { candidates.append(contentsOf: snapshot.articles) }
            }
            candidates.sort { $0.date > $1.date }
            var result: [RealArticle] = []
            var seen = Set<URL>()
            for article in candidates {
                guard let url = article.url, !article.title.isEmpty, seen.insert(url).inserted else { continue }
                let item = RealArticle(id: existingIDs[url] ?? article.id, title: article.title, source: article.source,
                                       date: article.date, url: url, imageURL: article.imageURL)
                result.append(item)
                if result.count == 100 { break }
            }
            return result
        }
        news = combine(false)
        transfers = combine(true)
        var newsFailures: [String] = []
        for feed in Self.feeds where !feed.transfers {
            if let message = failures[feed.id] { newsFailures.append(message) }
        }
        newsError = newsFailures.isEmpty ? nil : newsFailures.joined(separator: " ")
        errorMessage = failures.isEmpty ? nil : "تعذر تحديث بعض المصادر؛ الأخبار التي وصلت ما زالت معروضة."
        lastUpdated = snapshots.values.map(\.fetchedAt).min()
    }
}

private actor SportsImageRepository {
    static let shared = SportsImageRepository()
    private let cache = NSCache<NSURL, NSData>()
    private var pending: [URL: Task<Data, Error>] = [:]
    private let session: URLSession
    init() {
        cache.countLimit = 160; cache.totalCostLimit = 32 * 1024 * 1024
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 64 * 1024 * 1024, diskPath: "ninetyplus-images")
        config.timeoutIntervalForRequest = 12
        session = URLSession(configuration: config)
    }
    func data(for url: URL) async throws -> Data {
        if let hit = cache.object(forKey: url as NSURL) { return hit as Data }
        if let task = pending[url] { return try await task.value }
        let session = self.session
        let task = Task<Data, Error> {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  response.mimeType?.hasPrefix("image/") == true, data.count < 6_000_000 else { throw URLError(.badServerResponse) }
            return data
        }
        pending[url] = task
        defer { pending[url] = nil }
        let data = try await task.value
        cache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
        return data
    }
}

private struct SportsNetworkImage: View {
    let url: URL?
    let fit: Bool
    let fallback: String
    @State private var image: UIImage?
    @State private var loadedURL: URL?
    @State private var failed = false
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if loadedURL == url, let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: fit ? .fit : .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        .accessibilityIdentifier("sports.image.loaded")
                } else if url != nil && !failed {
                    ProgressView().tint(AppTheme.green).scaleEffect(0.7)
                } else {
                    Image(systemName: fallback).resizable().scaledToFit()
                        .padding(max(3, min(geometry.size.width, geometry.size.height) * 0.22))
                        .foregroundStyle(AppTheme.muted)
                }
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }
        .task(id: url) {
            image = nil; loadedURL = nil; failed = false
            guard let requested = url else { return }
            do {
                let data = try await SportsImageRepository.shared.data(for: requested)
                try Task.checkCancellation()
                let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1000, kCGImageSourceCreateThumbnailWithTransform: true]
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { failed = true; return }
                image = UIImage(cgImage: thumbnail); loadedURL = requested
            } catch { if !Task.isCancelled { failed = true } }
        }
    }
}

struct RemoteBadge: View {
    let url: String?
    private var isPlayer: Bool { (url?.lowercased() ?? "").contains("/players/") }
    private var isLeague: Bool { (url?.lowercased() ?? "").contains("/leagues/") }
    var body: some View {
        Group {
            if isPlayer {
                SportsNetworkImage(url: EditorialRSSParser.webURL(url), fit: false, fallback: "person.fill")
                    .background(AppTheme.cardRaised).clipShape(Circle()).overlay(Circle().stroke(AppTheme.border))
            } else {
                SportsNetworkImage(url: EditorialRSSParser.webURL(url), fit: true, fallback: isLeague ? "trophy" : "shield")
                    .padding(3).background(Color.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }.accessibilityHidden(true)
    }
}

struct EditorialArtwork: View {
    let article: RealArticle
    var body: some View {
        Group {
            if let url = article.imageURL { SportsNetworkImage(url: url, fit: false, fallback: "photo") }
            else {
                VStack(spacing: 8) {
                    Text(article.source).font(.caption.bold()).foregroundStyle(AppTheme.muted)
                    Image(systemName: "newspaper").foregroundStyle(AppTheme.muted)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.background(AppTheme.cardRaised).clipped().accessibilityHidden(true)
    }
}
