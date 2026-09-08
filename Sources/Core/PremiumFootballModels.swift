import Foundation

// Portable domain rules. No network, UI, invented provider data, or random IDs.
struct PulseFixture: Codable, Equatable, Identifiable {
    let id: String
    var leagueID: String? = nil
    var league = ""
    var homeID: String? = nil
    var home = ""
    var awayID: String? = nil
    var away = ""
    var homeScore: Int? = nil
    var awayScore: Int? = nil
    var kickoff: Date? = nil
    var status = "NS"
    var elapsed: Int? = nil
    var phase: String { status.uppercased() }
    var isLive: Bool { ["1H", "HT", "2H", "ET", "BT", "P", "LIVE", "INT"].contains(phase) }
    var isUpcoming: Bool { ["NS", "TBD"].contains(phase) }
    var isFinished: Bool { ["FT", "AET", "PEN"].contains(phase) }
    var valid: Bool {
        !id.isEmpty && id.utf8.count <= 240 &&
        [league, home, away, status].allSatisfy { $0.utf8.count <= 1000 } &&
        [leagueID, homeID, awayID].allSatisfy { ($0?.utf8.count ?? 0) <= 240 } &&
        [homeScore, awayScore].allSatisfy { $0.map { (0...1000).contains($0) } ?? true } &&
        (elapsed.map { (0...500).contains($0) } ?? true) &&
        (kickoff.map { $0.timeIntervalSince1970.isFinite } ?? true)
    }
    var hasScore: Bool { homeScore != nil && awayScore != nil }
    func scoreText(hidden: Bool) -> String {
        if hidden && !isUpcoming { return "النتيجة مخفية" }
        guard !isUpcoming, let homeScore, let awayScore else { return "—" }
        return "\(homeScore) - \(awayScore)"
    }
}

struct PulsePreferences {
    var teams: Set<String> = []
    var leagues: Set<String> = []
    var matches: Set<String> = []
    func follows(_ match: PulseFixture) -> Bool {
        matches.contains(match.id) || match.homeID.map { teams.contains($0) } == true ||
        match.awayID.map { teams.contains($0) } == true || match.leagueID.map { leagues.contains($0) } == true
    }
}

enum PulseRules {
    static func ranked(_ input: [PulseFixture], preferences: PulsePreferences, now: Date) -> [PulseFixture] {
        unique(input).sorted { a, b in
            let left = priority(a, preferences: preferences, now: now)
            let right = priority(b, preferences: preferences, now: now)
            if left != right { return left > right }
            if a.kickoff != b.kickoff { return (a.kickoff ?? .distantFuture) < (b.kickoff ?? .distantFuture) }
            return a.id < b.id
        }
    }
    static func unique(_ input: [PulseFixture]) -> [PulseFixture] {
        // A conflicting repeated ID is not trustworthy enough to derive a change.
        var values: [String: PulseFixture] = [:]
        var conflicts = Set<String>()
        for match in input where match.valid {
            if let old = values[match.id], old != match { conflicts.insert(match.id) }
            else { values[match.id] = match }
        }
        return values.values.filter { !conflicts.contains($0.id) }.sorted { $0.id < $1.id }
    }
    private static func priority(_ match: PulseFixture, preferences: PulsePreferences, now: Date) -> Int {
        var value = preferences.follows(match) ? 400 : 0
        if match.isLive { value += 100; if (match.elapsed ?? 0) >= 80 { value += 30 } }
        if match.isUpcoming, let kickoff = match.kickoff, (0...3600).contains(kickoff.timeIntervalSince(now)) { value += 60 }
        if match.isFinished { value += 10 }
        return value
    }
}

struct PulseChange: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case started, score, finished, status }
    let id: String
    let kind: Kind
    let match: PulseFixture
    let observedAt: Date
    let previousScore: String?
    var title: String {
        switch kind {
        case .started: return "رُصد بدء المباراة"
        case .score: return "تغيّرت النتيجة المسجلة"
        case .finished: return "رُصد انتهاء المباراة"
        case .status: return "تغيّرت حالة المباراة"
        }
    }
    static func between(_ previous: PulseFixture, _ next: PulseFixture, at: Date) -> PulseChange? {
        guard previous.id == next.id, previous.valid, next.valid else { return nil }
        let kind: Kind
        if !previous.isFinished && next.isFinished { kind = .finished }
        else if previous.isUpcoming && next.isLive { kind = .started }
        else if !next.isUpcoming, previous.hasScore, next.hasScore,
                previous.homeScore != next.homeScore || previous.awayScore != next.awayScore { kind = .score }
        else if previous.phase != next.phase { kind = .status }
        else { return nil }
        // This is receipt time, not the event's actual time or a claimed goal.
        return .init(id: "\(next.id)|\(at.timeIntervalSince1970)|\(kind.rawValue)", kind: kind,
                     match: next, observedAt: at, previousScore: previous.hasScore ? previous.scoreText(hidden: false) : nil)
    }
}

struct PulseEvent: Codable, Equatable, Identifiable {
    var minute: Int?
    var extra: Int?
    var team: String
    var player: String
    var type: String
    var detail: String
    var id: String {
        [minute.map(String.init) ?? "", extra.map(String.init) ?? "", team, player, type, detail]
            .map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
    }
    var valid: Bool {
        (minute.map { (0...200).contains($0) } ?? true) && (extra.map { (0...100).contains($0) } ?? true) &&
        [team, player, type, detail].allSatisfy { $0.utf8.count <= 2000 }
    }
    var clock: String {
        guard let minute else { return "—" }
        return (extra ?? 0) > 0 ? "\(minute)+\(extra!)′" : "\(minute)′"
    }
    var isRecordedGoal: Bool {
        type.lowercased() == "goal" && !detail.lowercased().contains("miss") &&
        !detail.lowercased().contains("cancel") && !detail.lowercased().contains("disallow")
    }
    var isRed: Bool {
        type.lowercased() == "card" && (detail.lowercased().contains("red") || detail.lowercased().contains("second yellow"))
    }
    static func ordered(_ events: [PulseEvent]) -> [PulseEvent] {
        var seen = Set<String>()
        return events.filter { $0.valid && seen.insert($0.id).inserted }.sorted {
            if $0.minute != $1.minute { return ($0.minute ?? Int.max) < ($1.minute ?? Int.max) }
            if $0.extra != $1.extra { return ($0.extra ?? 0) < ($1.extra ?? 0) }
            return $0.id < $1.id
        }
    }
    static func newSince(_ events: [PulseEvent], previous: Set<String>?) -> [PulseEvent] {
        guard let previous else { return [] } // First visit is a summary, never fake missed events.
        return ordered(events).filter { !previous.contains($0.id) }
    }
}

struct PremiumSeenMatch: Codable, Equatable {
    let eventIDs: [String]
    let seenAt: Date
}
struct PremiumFixtureSet: Codable, Equatable {
    let values: [PulseFixture]
    let receivedAt: Date
}
struct PremiumArticle: Codable, Equatable, Identifiable {
    let title: String
    let source: String
    let url: String
    let publishedAt: Date
    var id: String { url }
    var valid: Bool {
        !title.isEmpty && title.utf8.count <= 4000 && source.utf8.count <= 500 && url.utf8.count <= 4000 &&
        Self.safeURL(url) != nil && publishedAt.timeIntervalSince1970.isFinite
    }
    static func safeURL(_ text: String) -> URL? {
        guard let parts = URLComponents(string: text), ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              parts.user == nil, parts.password == nil, let host = parts.host, !host.isEmpty else { return nil }
        return parts.url
    }
    // An aggregator link or publication name never proves that a transfer is official.
    var provenance: String { "تقرير منشور • لا يُعد تأكيدًا رسميًا للصفقة" }
}

struct PremiumArchive: Codable, Equatable {
    static let maxBytes = 3_000_000
    private(set) var version = 1
    private(set) var latest = PremiumFixtureSet(values: [], receivedAt: .distantPast)
    private(set) var changes: [PulseChange] = []
    private(set) var baseline: [String: PulseFixture] = [:]
    private(set) var readAt: Date? = nil
    private(set) var seen: [String: PremiumSeenMatch] = [:]
    private(set) var teams: [String: PremiumFixtureSet] = [:]
    private(set) var savedArticles: [PremiumArticle] = []

    enum ArchiveError: Error { case invalid, full }
    var valid: Bool {
        version == 1 && latest.values.count <= 500 && latest.values.allSatisfy(\.valid) &&
        latest.receivedAt.timeIntervalSince1970.isFinite && changes.count <= 200 && baseline.count <= 1000 &&
        baseline.allSatisfy { $0.key == $0.value.id && $0.value.valid } &&
        changes.allSatisfy { $0.match.valid && $0.id.utf8.count <= 500 && $0.observedAt.timeIntervalSince1970.isFinite } &&
        seen.count <= 60 && seen.allSatisfy { $0.key.utf8.count <= 240 && $0.value.eventIDs.count <= 500 && $0.value.eventIDs.allSatisfy { $0.utf8.count <= 10_000 } && $0.value.seenAt.timeIntervalSince1970.isFinite } &&
        teams.count <= 30 && teams.allSatisfy { $0.key.utf8.count <= 240 && $0.value.values.count <= 100 && $0.value.values.allSatisfy(\.valid) && $0.value.receivedAt.timeIntervalSince1970.isFinite } &&
        savedArticles.count <= 100 && savedArticles.allSatisfy(\.valid) && Set(savedArticles.map(\.id)).count == savedArticles.count &&
        (readAt.map { $0.timeIntervalSince1970.isFinite } ?? true)
    }
    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maxBytes else { throw ArchiveError.invalid }
        let result = try JSONDecoder().decode(Self.self, from: data)
        guard result.valid else { throw ArchiveError.invalid }
        return result
    }
    func encode() throws -> Data {
        guard valid else { throw ArchiveError.invalid }
        let data = try JSONEncoder().encode(self)
        guard data.count <= Self.maxBytes else { throw ArchiveError.full }
        return data
    }
    @discardableResult mutating func observe(_ values: [PulseFixture], at time: Date) -> Bool {
        guard time.timeIntervalSince1970.isFinite, time > latest.receivedAt else { return false }
        let matches = Array(PulseRules.unique(values).prefix(500))
        // Bad/contradictory payloads are not an empty successful day.
        guard values.isEmpty || !matches.isEmpty else { return false }
        for match in matches {
            if let old = baseline[match.id], let change = PulseChange.between(old, match, at: time) { changes.append(change) }
            baseline[match.id] = match
        }
        latest = .init(values: matches, receivedAt: time)
        changes = Array(changes.filter { (0...7*86400).contains(time.timeIntervalSince($0.observedAt)) }.suffix(200))
        let retained = Set(matches.map(\.id) + changes.map { $0.match.id })
        if baseline.count > 1000 { baseline = baseline.filter { retained.contains($0.key) } }
        return true
    }
    mutating func markRead(at date: Date) {
        guard date.timeIntervalSince1970.isFinite else { return }
        readAt = max(readAt ?? .distantPast, date)
    }
    func unread(preferences: PulsePreferences, personalOnly: Bool) -> [PulseChange] {
        changes.filter { $0.observedAt > (readAt ?? .distantPast) && (!personalOnly || preferences.follows($0.match)) }
            .sorted { $0.observedAt == $1.observedAt ? $0.id < $1.id : $0.observedAt > $1.observedAt }
    }
    mutating func remember(matchID: String, events: [PulseEvent], at date: Date) {
        guard !matchID.isEmpty, matchID.utf8.count <= 240, date.timeIntervalSince1970.isFinite else { return }
        if let old = seen[matchID], old.seenAt > date { return }
        seen[matchID] = .init(eventIDs: Array(PulseEvent.ordered(events).prefix(500).map(\.id)), seenAt: date)
        if seen.count > 60, let oldest = seen.min(by: { $0.value.seenAt < $1.value.seenAt })?.key { seen[oldest] = nil }
    }
    mutating func cacheTeam(_ id: String, values: [PulseFixture], at date: Date) {
        guard !id.isEmpty, id.utf8.count <= 240, date.timeIntervalSince1970.isFinite else { return }
        if let old = teams[id], old.receivedAt > date { return }
        teams[id] = .init(values: Array(PulseRules.unique(values).prefix(100)), receivedAt: date)
        if teams.count > 30, let oldest = teams.min(by: { $0.value.receivedAt < $1.value.receivedAt })?.key { teams[oldest] = nil }
    }
    mutating func toggleArticle(_ article: PremiumArticle) throws {
        guard article.valid else { throw ArchiveError.invalid }
        if let index = savedArticles.firstIndex(where: { $0.id == article.id }) { savedArticles.remove(at: index) }
        else {
            guard savedArticles.count < 100 else { throw ArchiveError.full }
            savedArticles.insert(article, at: 0)
        }
    }
}

struct TeamFormReport {
    enum Venue: String, CaseIterable { case all = "الكل", home = "على أرضه", away = "خارج أرضه" }
    let teamID: String
    let matches: [PulseFixture]
    init(teamID: String, matches: [PulseFixture], venue: Venue = .all, limit: Int = 5, now: Date = Date()) {
        self.teamID = teamID
        self.matches = Array(PulseRules.unique(matches).filter { match in
            guard ["FT", "AET"].contains(match.phase), match.hasScore, let date = match.kickoff, date <= now,
                  match.homeID != match.awayID, match.homeID == teamID || match.awayID == teamID else { return false }
            return venue == .all || (venue == .home ? match.homeID == teamID : match.awayID == teamID)
        }.sorted { ($0.kickoff ?? .distantPast) > ($1.kickoff ?? .distantPast) }.prefix(max(0, min(limit, 20))))
    }
    var count: Int { matches.count }
    private func own(_ m: PulseFixture) -> Int { m.homeID == teamID ? m.homeScore! : m.awayScore! }
    private func opponent(_ m: PulseFixture) -> Int { m.homeID == teamID ? m.awayScore! : m.homeScore! }
    var wins: Int { matches.filter { own($0) > opponent($0) }.count }
    var draws: Int { matches.filter { own($0) == opponent($0) }.count }
    var losses: Int { count - wins - draws }
    var goalsFor: Int { matches.reduce(0) { $0 + own($1) } }
    var goalsAgainst: Int { matches.reduce(0) { $0 + opponent($1) } }
    var cleanSheets: Int { matches.filter { opponent($0) == 0 }.count }
    var formIndex: Int? { count >= 3 ? Int((Double(3*wins + draws) / Double(3*count) * 100).rounded()) : nil }
    var form: [String] { matches.map { own($0) == opponent($0) ? "ت" : own($0) > opponent($0) ? "ف" : "خ" } }
    static func headToHead(_ values: [PulseFixture], home: String, away: String) -> [PulseFixture] {
        guard !home.isEmpty, !away.isEmpty, home != away else { return [] }
        return PulseRules.unique(values).filter { match in
            match.isFinished && ((match.homeID == home && match.awayID == away) || (match.homeID == away && match.awayID == home))
        }.sorted { ($0.kickoff ?? .distantPast) > ($1.kickoff ?? .distantPast) }
    }
}

enum PremiumLineupRules {
    static func swapped(_ names: [String], from: Int, to: Int) -> [String]? {
        guard names.count == 11, names.indices.contains(from), names.indices.contains(to), from != to else { return nil }
        var result = names; result.swapAt(from, to); return result
    }
}
