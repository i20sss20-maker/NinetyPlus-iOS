import Foundation

enum FreeSourceTransport {
    static let gatewayKey = "ninetyplus.freeGatewayURL"
    static var defaultGateway: String { Bundle.main.object(forInfoDictionaryKey: "NINETYPLUS_FREE_GATEWAY_URL") as? String ?? "" }
    static func gateway(_ raw: String) -> URL? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/" else { return nil }
        return url
    }
    static func proxied(_ source: URL, base: URL) -> URL? {
        let path: String
        if source.host == "site.web.api.espn.com" {
            let prefixes = ["/apis/site/v2/sports/soccer/", "/apis/v2/sports/soccer/"]
            guard let prefix = prefixes.first(where: { source.path.hasPrefix($0) }) else { return nil }
            path = "free/espn/" + source.path.dropFirst(prefix.count)
        } else if source.host == "www.thesportsdb.com" {
            path = "free/directory/" + source.lastPathComponent
        } else { return nil }
        var url = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)
        url?.percentEncodedQuery = URLComponents(url: source, resolvingAgainstBaseURL: false)?.percentEncodedQuery
        return url?.url
    }
    static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        if let source = request.url,
           let base = gateway(UserDefaults.standard.string(forKey: gatewayKey) ?? defaultGateway),
           let url = proxied(source, base: base) {
            var proxy = request; proxy.url = url; proxy.timeoutInterval = 3
            do {
                let result = try await URLSession.shared.data(for: proxy)
                try Task.checkCancellation()
                if let http = result.1 as? HTTPURLResponse, (200..<300).contains(http.statusCode) { return result }
            } catch {
                if Task.isCancelled { throw CancellationError() }
            }
        }
        try Task.checkCancellation()
        return try await URLSession.shared.data(for: request)
    }
}
