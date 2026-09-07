import Foundation

/// Presentation rules for editorial reports, not a deal-verification system.
/// The title may report a denial or a rumour; it can never prove a signing.
enum EditorialPresentation {
    static func normalized(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ar"))
        let cleaned = folded.unicodeScalars.filter { scalar in
            !CharacterSet.nonBaseCharacters.contains(scalar) && scalar.value != 0x0640
        }.map(String.init).joined()
        return cleaned.replacingOccurrences(of: "أ", with: "ا")
            .replacingOccurrences(of: "إ", with: "ا").replacingOccurrences(of: "آ", with: "ا")
            .replacingOccurrences(of: "ى", with: "ي")
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func matches(_ article: RealArticle, query: String) -> Bool {
        let terms = normalized(query).split(separator: " ").map(String.init)
        let haystack = normalized(article.title + " " + article.source)
        return terms.allSatisfy { haystack.contains($0) }
    }

    static func isTransferTopic(_ title: String) -> Bool {
        let text = normalized(title)
        // Do not use "ضم": it also occurs in the name of Damac and in unrelated words.
        let terms = ["انتقال", "تعاقد", "صفقة", "صفقات", "اعارة", "الاعارات", "ميركاتو", "سوق الانتقالات", "transfer", "signing", "loan deal"]
        return terms.contains { text.contains(normalized($0)) }
    }

    static func safeURL(_ url: URL?) -> URL? {
        guard let url, ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }

    static func transferArticles(reports: [RealArticle], news: [RealArticle], now: Date = Date()) -> [RealArticle] {
        var candidates = reports + news.filter { isTransferTopic($0.title) }
        candidates = candidates.filter {
            safeURL($0.url) != nil && !normalized($0.title).isEmpty && $0.date <= now.addingTimeInterval(300)
        }
        candidates.sort {
            if $0.date != $1.date { return $0.date > $1.date }
            if $0.imageURL != nil && $1.imageURL == nil { return true }
            if $0.imageURL == nil && $1.imageURL != nil { return false }
            return ($0.url?.absoluteString ?? "") < ($1.url?.absoluteString ?? "")
        }
        var seenURLs = Set<URL>()
        var seenTitles = Set<String>()
        return candidates.filter { article in
            guard let url = safeURL(article.url) else { return false }
            let key = normalized(article.source) + "|" + normalized(article.title)
            guard !seenURLs.contains(url), !seenTitles.contains(key) else { return false }
            seenURLs.insert(url); seenTitles.insert(key)
            return true
        }
    }
}
