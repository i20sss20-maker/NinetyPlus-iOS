import Foundation

enum MatchDataSection: String, CaseIterable, Hashable {
    case fixture, events, stats, lineups, h2h

    var title: String {
        switch self {
        case .fixture: return "النتيجة والحالة"
        case .events: return "الأحداث"
        case .stats: return "الإحصائيات"
        case .lineups: return "التشكيلة"
        case .h2h: return "المواجهات"
        }
    }

    var maxAge: TimeInterval {
        switch self {
        case .fixture: return 15
        case .events: return 30
        case .stats: return 60
        case .lineups: return 300
        case .h2h: return 3600
        }
    }
}

/// Metadata only: true means a successful nonempty payload, false an empty one.
/// Each endpoint owns its request token; a failed endpoint cannot clear another.
struct MatchCenterProgress {
    private(set) var matchID: String?
    private var resources: [MatchDataSection: PageResource<Bool>] = [:]
    private var unavailable: Set<MatchDataSection> = []

    @discardableResult
    mutating func select(matchID id: String) -> Bool {
        guard matchID != id else { return false }
        matchID = id
        resources = [:]
        unavailable = []
        return true
    }

    func state(_ section: MatchDataSection) -> PageResource<Bool> {
        resources[section] ?? PageResource<Bool>()
    }

    mutating func begin(_ section: MatchDataSection, force: Bool = false, now: Date = Date()) -> UUID? {
        guard let matchID else { return nil }
        var resource = state(section)
        let key = "\(matchID):\(section.rawValue)"
        if !force && (resource.isLoading || resource.isFresh(key: key, maxAge: section.maxAge, now: now) || unavailable.contains(section)) { return nil }
        unavailable.remove(section)
        let token = resource.begin(key: key)
        resources[section] = resource
        return token
    }

    @discardableResult
    mutating func succeed(_ section: MatchDataSection, token: UUID, hasContent: Bool, at date: Date = Date()) -> Bool {
        var resource = state(section)
        guard resource.succeed(hasContent, token: token, at: date) else { return false }
        resources[section] = resource
        return true
    }

    mutating func fail(_ section: MatchDataSection, token: UUID, message: String) {
        var resource = state(section)
        if resource.fail(message, token: token) { resources[section] = resource }
    }

    mutating func cancel(_ section: MatchDataSection, token: UUID) {
        var resource = state(section)
        resource.cancel(token: token)
        resources[section] = resource
    }

    mutating func markUnavailable(_ section: MatchDataSection) {
        unavailable.insert(section)
        resources[section] = nil
    }

    mutating func markAvailable(_ section: MatchDataSection) {
        unavailable.remove(section)
    }

    mutating func invalidate() {
        for key in Array(resources.keys) {
            var resource = state(key)
            resource.invalidate()
            resources[key] = resource
        }
    }

    func mayShowEmpty(_ section: MatchDataSection) -> Bool {
        let resource = state(section)
        return unavailable.contains(section) || (resource.value == false && !resource.isLoading && resource.errorMessage == nil)
    }

    var errors: [(MatchDataSection, String)] {
        MatchDataSection.allCases.compactMap { section in
            state(section).errorMessage.map { (section, $0) }
        }
    }
}

enum MatchLivePolicy {
    enum Notice: Equatable { case started, scoreChanged, finished }

    static func isLive(_ status: String) -> Bool {
        ["1H", "HT", "2H", "ET", "BT", "P", "LIVE", "INT"].contains(status.uppercased())
    }

    static func interval(status: String, kickoff: Date?, now: Date = Date()) -> TimeInterval? {
        if FixturePhase.isFinished(status) { return nil }
        if isLive(status) { return 30 }
        if status.uppercased() == "SUSP" { return 120 }
        guard FixturePhase.isUpcoming(status) else { return nil }
        guard let kickoff else { return 300 }
        let untilKickoff = kickoff.timeIntervalSince(now)
        return (-10800...900).contains(untilKickoff) ? 30 : 300
    }

    static func notice(previousStatus: String, status: String, previousHome: Int?, previousAway: Int?, home: Int?, away: Int?) -> Notice? {
        // Finishing takes priority over a simultaneous last-minute score update.
        if !FixturePhase.isFinished(previousStatus) && FixturePhase.isFinished(status) { return .finished }
        if FixturePhase.isUpcoming(previousStatus) && isLive(status) { return .started }
        guard !FixturePhase.isUpcoming(status),
              let previousHome, let previousAway, let home, let away,
              previousHome != home || previousAway != away else { return nil }
        return .scoreChanged
    }

    static func statusText(_ status: String, elapsed: Int?) -> String {
        switch status.uppercased() {
        case "NS": return "لم تبدأ"
        case "TBD": return "الموعد غير محدد"
        case "HT": return "بين الشوطين"
        case "BT": return "استراحة الوقت الإضافي"
        case "ET": return "وقت إضافي"
        case "P": return "ركلات ترجيح جارية"
        case "FT": return "انتهت"
        case "AET": return "انتهت بعد وقت إضافي"
        case "PEN": return "انتهت بركلات الترجيح"
        case "PST": return "مؤجلة"
        case "CANC": return "ملغاة"
        case "SUSP": return "موقوفة مؤقتًا"
        case "INT": return "متوقفة مؤقتًا"
        case "ABD": return "لم تُستكمل"
        case "AWD": return "نتيجة بقرار إداري"
        case "WO": return "فوز بالانسحاب"
        default:
            if isLive(status) { return elapsed.map { "مباشر • \($0)′" } ?? "مباشر" }
            return status.isEmpty ? "الحالة غير متاحة" : status
        }
    }

    static func summary(status: String, homeName: String, awayName: String, home: Int?, away: Int?) -> String {
        if FixturePhase.isUpcoming(status) { return "المباراة لم تبدأ بعد. نعرض المعلومات المنشورة قبل انطلاقها." }
        guard let home, let away else { return "لا توجد نتيجة منشورة حاليًا. نعرض فقط المعلومات المتاحة من المصدر." }
        if status.uppercased() == "PEN" {
            return "انتهت المباراة بركلات الترجيح. نتيجة اللعب المسجلة: \(homeName) \(home)-\(away) \(awayName). لا تحدد هذه الأرقام نتيجة ركلات الترجيح."
        }
        if FixturePhase.isFinished(status) {
            if home == away { return "انتهت المباراة بالتعادل \(home)-\(away)." }
            let winner = home > away ? homeName : awayName
            return "انتهت المباراة بفوز \(winner). النتيجة: \(homeName) \(home)-\(away) \(awayName)."
        }
        // A score in an interrupted or administratively resolved game is not live.
        guard isLive(status) else { return "\(statusText(status, elapsed: nil)). النتيجة المسجلة: \(homeName) \(home)-\(away) \(awayName)." }
        if home == away { return "المباراة متعادلة \(home)-\(away)." }
        let leader = home > away ? homeName : awayName
        return "\(leader) متقدم حاليًا. النتيجة: \(homeName) \(home)-\(away) \(awayName)."
    }

    static func eventMinute(elapsed: Int?, extra: Int?) -> String {
        guard let elapsed else { return "—" }
        if let extra, extra > 0 { return "\(elapsed)+\(extra)′" }
        return "\(elapsed)′"
    }
}
