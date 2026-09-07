import Foundation

@main struct EditorialFeedTests {
    static func main() throws {
        func feed(_ body: String) -> Data { Data("<rss version=\"2.0\" xmlns:media=\"http://search.yahoo.com/mrss/\"><channel>\(body)</channel></rss>".utf8) }
        let base = "<title><![CDATA[خبر &amp; عنوان - الناشر]]></title><source>الناشر</source><link>https://example.org/article</link><pubDate>Mon, 07 Sep 2026 10:00:00 GMT</pubDate>"
        func read(_ body: String) throws -> [RealArticle] { try EditorialRSSParser(data: feed(body), source: "الناشر").parse() }
        let thumbnail = try read("<item>\(base)<media:thumbnail url=\"https://example.org/photo.jpg\" width=\"600\"/></item>")
        precondition(thumbnail.count == 1 && thumbnail[0].imageURL?.lastPathComponent == "photo.jpg")
        precondition(thumbnail[0].title == "خبر & عنوان")
        let enclosure = try read("<item>\(base)<enclosure url=\"https://example.org/p.png\" type=\"image/png\"/></item>")
        precondition(enclosure[0].imageURL != nil)
        let cdata = try read("<item>\(base)<description><![CDATA[<img src='https://example.org/story.jpg'>]]></description></item>")
        precondition(cdata[0].imageURL?.lastPathComponent == "story.jpg")
        let plain = try read("<item>\(base)</item>")
        precondition(plain[0].imageURL == nil, "Missing photographs must stay missing")
        let undated = try read("<item><title>عنوان</title><link>https://example.org/a</link></item>")
        precondition(undated.isEmpty, "An unknown date must not become today's date")
        precondition(EditorialRSSParser.webURL("javascript:alert(1)") == nil)
        precondition(EditorialRSSParser.webURL("https://user:password@example.org") == nil)
        do { _ = try EditorialRSSParser(data: Data("<html>error</html>".utf8), source: "x").parse(); fatalError("HTML accepted as feed") } catch {}
        do { _ = try EditorialRSSParser(data: Data("<rss><channel><item>".utf8), source: "x").parse(); fatalError("Broken XML accepted") } catch {}
        let best = try read("<item>\(base)<media:thumbnail url=\"https://example.org/s.jpg\" width=\"120\"/><media:thumbnail url=\"https://example.org/l.jpg\" width=\"800\"/></item>")
        precondition(best[0].imageURL?.lastPathComponent == "l.jpg")
        let isolated = try read("<item>\(base)<media:thumbnail url=\"https://example.org/s.jpg\"/></item><item>\(base)</item>")
        precondition(isolated.count == 2 && isolated[1].imageURL == nil, "No photograph may leak into the next article")
        print("PASS: 12 editorial parsing and image-association checks")
    }
}
