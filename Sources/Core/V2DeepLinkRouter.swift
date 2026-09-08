import Foundation

enum V2DeepLinkRouter {
    static func tab(for url: URL) -> Int? {
        guard url.scheme?.lowercased() == "ninetyplus" else { return nil }
        let route = [url.host, url.pathComponents.dropFirst().first]
            .compactMap { $0?.lowercased() }
            .first { !$0.isEmpty }
        switch route {
        case "home", "الرئيسية": return 0
        case "matches", "match", "المباريات": return 1
        case "search", "discover", "البحث": return 2
        case "news", "الأخبار": return 3
        case "more", "settings", "المزيد": return 4
        default: return nil
        }
    }

    static let examples = [
        "ninetyplus://home",
        "ninetyplus://matches",
        "ninetyplus://search",
        "ninetyplus://news",
        "ninetyplus://more"
    ]
}
