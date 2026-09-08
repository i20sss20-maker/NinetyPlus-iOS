import Foundation

@main struct PremiumFootballTests {
    static var assertions = 0
    static func check(_ value: Bool, _ message: String) { assertions += 1; if !value { fatalError(message) } }
    static let now = Date(timeIntervalSince1970: 1_788_890_000)
    static func match(_ id: String = "np:one", phase: String = "NS", h: Int? = nil, a: Int? = nil, offset: Double = -1000) -> PulseFixture {
        PulseFixture(id: id, leagueID: "307", league: "الدوري", homeID: "1", home: "أ", awayID: "2", away: "ب", homeScore: h, awayScore: a, kickoff: now.addingTimeInterval(offset), status: phase)
    }
    static func rejects(_ data: Data) {
        do { _ = try PremiumArchive.decode(data); fatalError("corruption accepted") }
        catch { assertions += 1 }
    }
    static func main() throws {
        let empty = PremiumArchive()
        check(try PremiumArchive.decode(empty.encode()) == empty, "empty archive round trip")
        check(!match(phase: "NS").isLive, "upcoming cannot be live")
        for phase in ["1H", "HT", "2H", "ET", "BT", "P", "LIVE", "INT"] { check(match(phase: phase.lowercased()).isLive, "live phase mapping") }
        for phase in ["FT", "AET", "PEN"] { check(match(phase: phase).isFinished, "finished phase mapping") }
        for phase in ["PST", "CANC", "SUSP", "ABD", "AWD", "WO"] { check(!match(phase: phase).isFinished && !match(phase: phase).isLive, "administrative status misclassified") }
        check(match(phase: "FT", h: 2, a: 1).scoreText(hidden: true) == "النتيجة مخفية", "spoiler leaked")
        check(match(phase: "NS", h: 0, a: 0).scoreText(hidden: false) == "—", "upcoming score shown")
        check(match(phase: "FT", h: 0, a: 0).scoreText(hidden: false) == "0 - 0", "known zero erased")
        check(match(phase: "FT", h: nil, a: 0).scoreText(hidden: false) == "—", "unknown score invented")
        check(!match(h: -1).valid, "negative score accepted")
        check(PulseRules.unique([match(), match()]).count == 1, "duplicate should coalesce")
        check(PulseRules.unique([match(), match(phase: "FT", h: 2, a: 1)]).isEmpty, "conflicting identity cannot derive a truth")
        let personal = PulsePreferences(teams: ["1"])
        check(personal.follows(match()), "followed team not found")
        var external = match(); external.homeID = "espn:1"; external.awayID = "espn:2"
        check(!personal.follows(external), "provider ID namespaces collided")
        let preferred = match("fav", phase: "NS", offset: 36000)
        var other = match("other", phase: "1H", h: 0, a: 0); other.homeID = "3"; other.awayID = "4"
        check(PulseRules.ranked([other, preferred], preferences: personal, now: now).first?.id == "fav", "favorites order")
        check(PulseRules.ranked([match("b"), match("a")], preferences: .init(), now: now).map(\.id) == ["a", "b"], "tie order is unstable")
        var archive = PremiumArchive()
        check(archive.observe([match()], at: now), "first baseline not saved")
        check(archive.changes.isEmpty, "first visit generated fake changes")
        check(!archive.observe([match(phase: "FT", h: 2, a: 1)], at: now), "same timestamp accepted")
        check(!archive.observe([match(phase: "FT", h: 2, a: 1)], at: now.addingTimeInterval(-1)), "older response accepted")
        archive.observe([match(phase: "1H", h: 0, a: 0)], at: now.addingTimeInterval(1))
        check(archive.changes.last?.kind == .started, "start missing")
        archive.observe([match(phase: "1H", h: 1, a: 0)], at: now.addingTimeInterval(2))
        check(archive.changes.last?.kind == .score, "score change missing")
        archive.observe([match(phase: "1H", h: 0, a: 0)], at: now.addingTimeInterval(3))
        check(archive.changes.last?.kind == .score && archive.changes.last?.title == "تغيّرت النتيجة المسجلة", "correction falsely claimed as a goal")
        archive.observe([match(phase: "FT", h: 2, a: 0)], at: now.addingTimeInterval(4))
        check(archive.changes.last?.kind == .finished, "finish must win over score")
        let count = archive.changes.count
        archive.observe([], at: now.addingTimeInterval(5))
        check(archive.changes.count == count && archive.baseline.count == 1, "disappearing fixture fabricated finish")
        archive.observe([match("new", phase: "FT", h: 7, a: 0)], at: now.addingTimeInterval(6))
        check(archive.changes.count == count, "newly discovered fixture generated a false delta")
        archive.markRead(at: now.addingTimeInterval(3))
        check(archive.unread(preferences: personal, personalOnly: true).count == 1, "unread cutoff wrong")
        archive.markRead(at: now)
        check(archive.readAt == now.addingTimeInterval(3), "read marker went backwards")
        check(archive.unread(preferences: .init(teams: ["999"]), personalOnly: true).isEmpty, "personal brief leaked unrelated games")
        check(try PremiumArchive.decode(archive.encode()) == archive, "populated archive round trip")
        let unknown = match("same", phase: "1H")
        check(PulseChange.between(unknown, match("same", phase: "1H", h: 2, a: 1), at: now) == nil, "missing score became a scored goal")
        let event = PulseEvent(minute: 45, extra: 3, team: "أ", player: "ب", type: "Goal", detail: "Normal Goal")
        check(event.clock == "45+3′", "added time formatting")
        check(event.isRecordedGoal && !event.isRed, "goal classification")
        var missed = event; missed.detail = "Missed Penalty"
        check(!missed.isRecordedGoal, "missed penalty counted as goal")
        var cancelled = event; cancelled.detail = "Goal cancelled"
        check(!cancelled.isRecordedGoal, "cancelled goal counted")
        var red = event; red.type = "Card"; red.detail = "Second Yellow card"
        check(red.isRed && !red.isRecordedGoal, "second yellow not red")
        var bad = event; bad.minute = -1
        check(!bad.valid && PulseEvent.ordered([bad]).isEmpty, "invalid event time accepted")
        var early = event; early.extra = 1
        check(PulseEvent.ordered([event, early, event]).map(\.extra) == [1, 3], "event sort or dedup failed")
        check(PulseEvent.newSince([event], previous: nil).isEmpty, "first visit falsely missed event")
        check(PulseEvent.newSince([event, red], previous: [event.id]) == [red], "seen-event diff failed")
        archive.remember(matchID: "one", events: [event, event], at: now)
        archive.remember(matchID: "one", events: [red], at: now.addingTimeInterval(-1))
        check(archive.seen["one"]?.eventIDs == [event.id], "old read overwrote new read")
        for i in 0..<70 { archive.remember(matchID: "m\(i)", events: [event], at: now.addingTimeInterval(Double(i))) }
        check(archive.seen.count == 60, "seen cache not bounded")
        for i in 0..<35 { archive.cacheTeam("t\(i)", values: [match()], at: now.addingTimeInterval(Double(i))) }
        check(archive.teams.count == 30, "team cache not bounded")
        archive.cacheTeam("t34", values: [], at: now)
        check(archive.teams["t34"]?.values.count == 1, "older cache won")
        let samples = [match("a", phase: "FT", h: 2, a: 0), match("b", phase: "FT", h: 1, a: 1), match("c", phase: "FT", h: 0, a: 1)]
        let report = TeamFormReport(teamID: "1", matches: samples, now: now)
        check(report.count == 3 && report.wins == 1 && report.draws == 1 && report.losses == 1, "form WDL incorrect")
        check(report.goalsFor == 3 && report.goalsAgainst == 2 && report.cleanSheets == 1, "team totals incorrect")
        check(report.formIndex == 44, "form formula incorrect")
        check(TeamFormReport(teamID: "1", matches: Array(samples.prefix(2)), now: now).formIndex == nil, "tiny sample got index")
        check(TeamFormReport(teamID: "1", matches: samples, venue: .away, now: now).count == 0, "venue filter wrong")
        let penalties = match("p", phase: "PEN", h: 1, a: 1)
        check(TeamFormReport(teamID: "1", matches: [penalties], now: now).count == 0, "shootout outcome inferred from regular score")
        check(TeamFormReport(teamID: "1", matches: [match("future", phase: "FT", h: 1, a: 0, offset: 1000)], now: now).count == 0, "future match used for form")
        check(TeamFormReport(teamID: "1", matches: samples + samples, now: now).count == 3, "double counted form")
        for n in 3...20 {
            let wins = (0..<n).map { match("\($0)", phase: "FT", h: 1, a: 0) }
            check(TeamFormReport(teamID: "1", matches: wins, limit: n, now: now).formIndex == 100, "all wins index")
            check(TeamFormReport(teamID: "2", matches: wins, limit: n, now: now).formIndex == 0, "all losses index")
        }
        check(TeamFormReport.headToHead(samples + [other], home: "1", away: "2").count == 3, "H2H filter")
        check(TeamFormReport.headToHead(samples, home: "1", away: "1").isEmpty, "same team H2H")
        let article = PremiumArticle(title: "خبر", source: "المصدر", url: "https://example.com/news/1", publishedAt: now)
        check(article.valid && article.provenance.contains("لا يُعد تأكيدًا"), "news truth label")
        for url in ["javascript:alert(1)", "file:///private", "https://user:pass@example.com", "https://"] {
            check(PremiumArticle.safeURL(url) == nil, "unsafe news URL")
        }
        try archive.toggleArticle(article); check(archive.savedArticles.count == 1, "save article")
        try archive.toggleArticle(article); check(archive.savedArticles.isEmpty, "unsave article")
        for i in 0..<100 { try archive.toggleArticle(.init(title: "خبر", source: "م", url: "https://example.com/\(i)", publishedAt: now)) }
        do { try archive.toggleArticle(article); fatalError("saved-news limit missing") } catch { assertions += 1 }
        check(archive.savedArticles.count == 100, "limit discarded saved items")
        let names = (0..<11).map(String.init)
        check(PremiumLineupRules.swapped(names, from: 0, to: 10)?.first == "10", "lineup swap")
        check(PremiumLineupRules.swapped(names, from: -1, to: 0) == nil, "negative lineup index")
        check(PremiumLineupRules.swapped([], from: 0, to: 1) == nil, "corrupt lineup accepted")
        check(PremiumLineupRules.swapped(names, from: 0, to: 0) == nil, "self swap accepted")
        check(try PremiumArchive.decode(archive.encode()) == archive, "all fields round trip")
        rejects(Data("not json".utf8)); rejects(Data(repeating: 0, count: PremiumArchive.maxBytes + 1))
        var json = try JSONSerialization.jsonObject(with: archive.encode()) as! [String: Any]
        json["version"] = 2; rejects(try JSONSerialization.data(withJSONObject: json))
        json["version"] = 1; json["savedArticles"] = ["bad"]; rejects(try JSONSerialization.data(withJSONObject: json))
        print("Premium domain tests: \(assertions) assertions passed")
    }
}
