import Foundation

@main struct EditorialPresentationTests {
    static func main() {
        var count = 0
        func check(_ condition: Bool, _ name: String) {
            precondition(condition, "FAIL: \(name)"); count += 1
        }
        let now = Date(timeIntervalSince1970: 1_788_800_000)
        func article(_ title: String, source: String = "الصحيفة", path: String = "1", age: Double = 0, photo: Bool = false) -> RealArticle {
            RealArticle(title: title, source: source, date: now.addingTimeInterval(-age),
                        url: URL(string: "https://example.test/\(path)"), imageURL: photo ? URL(string: "https://example.test/photo.jpg") : nil)
        }
        check(EditorialPresentation.normalized("  الاتِّحَاد  ") == "الاتحاد", "Arabic diacritics removed")
        check(EditorialPresentation.normalized("الأَهـلي") == "الاهلي", "Hamza and tatweel normalized")
        check(EditorialPresentation.normalized("  Loan\n DEAL ") == "loan deal", "Latin case and whitespace")
        let report = article("الأهلي ينفي التعاقد مع اللاعب", source: "صحيفة الاتحاد")
        check(EditorialPresentation.matches(report, query: "اهلي تعاقد"), "Search matches normalized multiword query")
        check(EditorialPresentation.matches(report, query: "الاتحاد"), "Search includes source")
        check(EditorialPresentation.matches(report, query: " \n "), "Empty query matches")
        check(!EditorialPresentation.matches(report, query: "ميسي"), "Unrelated search fails")
        check(EditorialPresentation.isTransferTopic(report.title), "A denial is a transfer report, not a confirmed deal")
        check(EditorialPresentation.isTransferTopic("صفقات جديدة في الدوري"), "Plural deals")
        check(EditorialPresentation.isTransferTopic("نهاية إعارة اللاعب"), "Arabic loan topic")
        check(EditorialPresentation.isTransferTopic("Transfer talks have ended"), "English reports")
        check(!EditorialPresentation.isTransferTopic("ضمك يفوز على منافسه"), "Damac is not a transfer keyword")
        check(!EditorialPresentation.isTransferTopic("هدف في الوقت بدل الضائع"), "Unrelated match report excluded")
        check(EditorialPresentation.safeURL(URL(string: "https://example.test/a")) != nil, "HTTPS article link")
        check(EditorialPresentation.safeURL(URL(string: "http://example.test/a")) != nil, "Existing HTTP links retained")
        for raw in ["file:///tmp/a", "javascript:alert(1)", "/relative", "https://user:password@example.test/a"] {
            check(EditorialPresentation.safeURL(URL(string: raw)) == nil, "Unsafe URL rejected: \(raw)")
        }
        let items = EditorialPresentation.transferArticles(reports: [report, report], news: [article("تعاقد جديد", path: "2", age: 1, photo: true), article("مباراة اليوم", path: "3")], now: now)
        check(items.count == 2, "Duplicate link and unrelated news omitted")
        check(items.first?.title == report.title, "Newest first")
        check(items.last?.imageURL != nil, "Original photograph preserved")
        let two = EditorialPresentation.transferArticles(reports: [article("الخبر", path: "1"), article("الخبر", path: "2")], news: [], now: now)
        check(two.count == 1, "Same publisher/title not repeated via aggregation")
        check(EditorialPresentation.transferArticles(reports: [article("خبر", age: -3600)], news: [], now: now).isEmpty, "Future publication not shown as breaking news")
        check(EditorialPresentation.transferArticles(reports: [article(" \n ")], news: [], now: now).isEmpty, "Empty title omitted")
        check(EditorialPresentation.transferArticles(reports: [article("رسميًا: النادي ينفي الصفقة")], news: [], now: now).first?.title == "رسميًا: النادي ينفي الصفقة", "Publisher wording is preserved without inventing verification")
        print("PASS: \(count) editorial presentation checks")
    }
}
