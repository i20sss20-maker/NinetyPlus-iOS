import Foundation
import SwiftUI

extension APIPlusMatch {
    var pulseSnapshot: PulseFixture {
        PulseFixture(id: id, leagueID: leagueID, league: SportsArabic.league(league),
                     homeID: homeID, home: SportsArabic.team(home), awayID: awayID, away: SportsArabic.team(away),
                     homeScore: homeScore, awayScore: awayScore, kickoff: date, status: status, elapsed: elapsed)
    }
}
extension PulseFixture {
    var appMatch: APIPlusMatch {
        APIPlusMatch(id: id, leagueID: leagueID, league: league, leagueLogo: nil,
                     homeID: homeID, home: home, homeLogo: nil, awayID: awayID, away: away, awayLogo: nil,
                     homeScore: homeScore, awayScore: awayScore, date: kickoff, status: status, elapsed: elapsed)
    }
}
extension APIEventItem {
    var pulseEvent: PulseEvent {
        PulseEvent(minute: time.elapsed, extra: time.extra, team: SportsArabic.team(team.name ?? ""),
                   player: player.name ?? "", type: type ?? "", detail: detail ?? "")
    }
}
extension RealArticle {
    var premiumArticle: PremiumArticle? {
        guard let url else { return nil }
        let value = PremiumArticle(title: title.englishDigits, source: source, url: url.absoluteString, publishedAt: date)
        return value.valid ? value : nil
    }
}

@MainActor final class PremiumFootballStore: ObservableObject {
    static let shared = PremiumFootballStore()
    @Published private(set) var archive = PremiumArchive()
    @Published private(set) var storageWarning: String?
    private let defaults: UserDefaults
    private let key = "ninetyplus.premium.archive.v1"
    private var canWrite = true
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key) {
            do { archive = try PremiumArchive.decode(data) }
            catch { canWrite = false; storageWarning = "تعذر قراءة البيانات المحفوظة. لم نحذفها أو نستبدلها." }
        }
    }
    func observe(_ matches: [APIPlusMatch], receivedAt: Date) {
        guard archive.observe(matches.map(\.pulseSnapshot), at: receivedAt) else { return }
        save()
    }
    func markRead() { archive.markRead(at: Date()); save() }
    func remember(matchID: String, events: [PulseEvent]) {
        archive.remember(matchID: matchID, events: events, at: Date()); save()
    }
    func cacheTeam(id: String, matches: [APIPlusMatch]) {
        archive.cacheTeam(id, values: matches.map(\.pulseSnapshot), at: Date()); save()
    }
    func toggle(_ article: PremiumArticle) {
        do { try archive.toggleArticle(article); save() }
        catch { storageWarning = "تعذر الحفظ؛ الحد الأقصى 100 خبر. الأخبار المحفوظة لم تُحذف." }
    }
    private func save() {
        guard canWrite else { return }
        do {
            let data = try archive.encode()
            defaults.set(data, forKey: key)
            storageWarning = nil
        } catch { storageWarning = "تعذر حفظ آخر التغييرات. النسخة السابقة على الجهاز لم تُستبدل." }
    }
}

@MainActor final class PremiumTeamLoader: ObservableObject {
    @Published private(set) var state = PageResource<[PulseFixture]>()
    func load(id: String, name: String) async {
        guard !Task.isCancelled else { return }
        let token = state.begin(key: id)
        defer { state.cancel(token: token) }
        do {
            let values = try await APISportsStore.shared.teamFixtures(teamID: id, teamName: name, next: false)
            try Task.checkCancellation()
            guard state.succeed(values.map(\.pulseSnapshot), token: token) else { return }
            PremiumFootballStore.shared.cacheTeam(id: id, matches: values)
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            if let cached = PremiumFootballStore.shared.archive.teams[id],
               (0...7*86400).contains(Date().timeIntervalSince(cached.receivedAt)) {
                state.succeed(cached.values, token: token, warning: "تعذر التحديث. هذه عينة محفوظة بتاريخ موضح، وليست بيانات مباشرة.", at: cached.receivedAt)
            } else { state.fail(error.localizedDescription, token: token) }
        }
    }
    func cancel() { state.invalidate() }
}
