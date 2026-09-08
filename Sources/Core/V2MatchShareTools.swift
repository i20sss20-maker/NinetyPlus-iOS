import Foundation

enum V2MatchShareTools {
    static func summary(_ match: APIPlusMatch) -> String {
        let home = SportsArabic.team(match.home)
        let away = SportsArabic.team(match.away)
        let league = SportsArabic.league(match.league)
        let status = MatchLivePolicy.statusText(match.status, elapsed: match.elapsed)
        var parts = ["90+", league, "\(home) ضد \(away)", status]
        if !FixturePhase.isUpcoming(match.status), let h = match.homeScore, let a = match.awayScore {
            parts.insert("\(home) \(h) - \(a) \(away)", at: 3)
        } else if let date = match.date {
            parts.insert(SportsDisplayDate.label(date, pattern: "EEEE، d MMMM - HH:mm"), at: 3)
        }
        return parts.joined(separator: "\n").englishDigits
    }

    static func h2hSummary(current: APIPlusMatch, matches: [APIPlusMatch]) -> String? {
        let finished = matches.filter { FixturePhase.isFinished($0.status) && $0.homeScore != nil && $0.awayScore != nil }
        guard !finished.isEmpty else { return nil }
        let homeName = current.home
        let awayName = current.away
        var homeWins = 0, awayWins = 0, draws = 0
        for match in finished.prefix(5) {
            guard let h = match.homeScore, let a = match.awayScore else { continue }
            if h == a { draws += 1; continue }
            let winner = h > a ? match.home : match.away
            if sameTeam(winner, homeName) { homeWins += 1 }
            else if sameTeam(winner, awayName) { awayWins += 1 }
        }
        return "آخر \(min(5, finished.count)) مواجهات: \(SportsArabic.team(homeName)) \(homeWins) فوز، \(draws) تعادل، \(SportsArabic.team(awayName)) \(awayWins) فوز".englishDigits
    }

    static func phaseSummary(_ match: APIPlusMatch) -> String {
        if FixturePhase.isUpcoming(match.status) {
            if let date = match.date {
                return "قبل المباراة • \(SportsDisplayDate.label(date, pattern: "EEEE، d MMMM - HH:mm"))"
            }
            return "قبل المباراة"
        }
        if MatchLivePolicy.isLive(match.status) {
            return "المباراة جارية الآن • \(MatchLivePolicy.statusText(match.status, elapsed: match.elapsed))".englishDigits
        }
        if let h = match.homeScore, let a = match.awayScore {
            if h == a { return "بعد المباراة • انتهت بالتعادل \(h) - \(a)".englishDigits }
            let winner = h > a ? match.home : match.away
            return "بعد المباراة • فاز \(SportsArabic.team(winner)) بنتيجة \(h) - \(a)".englishDigits
        }
        return "بعد المباراة"
    }

    private static func sameTeam(_ lhs: String, _ rhs: String) -> Bool {
        let a = lhs.lowercased().replacingOccurrences(of: "-", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let b = rhs.lowercased().replacingOccurrences(of: "-", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return a == b || SportsArabic.team(lhs) == SportsArabic.team(rhs)
    }
}
