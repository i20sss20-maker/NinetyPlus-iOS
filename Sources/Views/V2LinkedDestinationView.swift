import SwiftUI

@MainActor struct V2LinkedDestinationView: View {
    let route: V2ContentRoute
    @Environment(\.dismiss) private var dismiss
    @State private var resource = PageResource<Destination>()
    @State private var retry = 0
    private enum Destination {
        case match(APIPlusMatch), team(APIPlusTeam), player(APIPlusPlayer), league(LeagueOption)
    }
    private enum LinkError: LocalizedError {
        case unavailable
        var errorDescription: String? { "المحتوى المرتبط غير متاح حاليًا. أعد المحاولة أو ارجع للتطبيق." }
    }
    var body: some View {
        NavigationStack {
            Group {
                if let value = resource.value, resource.key == route.id {
                    switch value {
                    case .match(let match): V2MatchCenterView(match: match)
                    case .team(let team): V2TeamView(team: team)
                    case .player(let player): V2PlayerView(player: player)
                    case .league(let league): V2LeagueHubView(league: league)
                    }
                } else {
                    VStack(spacing: 16) {
                        Text("فتح المحتوى المرتبط").font(.headline)
                        PageLoadFeedback(loading: resource.isLoading || resource.key == nil, hasValue: false,
                                         message: resource.errorMessage, updatedAt: nil) { retry += 1 }
                    }
                }
            }
            .background(AppTheme.bg.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } } }
        }
        .task(id: "\(route.id)|\(retry)") { await load() }
        .onDisappear { resource.invalidate() }
    }
    private func load() async {
        guard !Task.isCancelled else { return }
        let token = resource.begin(key: route.id)
        defer { resource.cancel(token: token) }
        do {
            let value = try await resolve()
            try Task.checkCancellation()
            resource.succeed(value, token: token)
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            resource.fail(error.localizedDescription, token: token)
        }
    }
    private func resolve() async throws -> Destination {
        switch route.kind {
        case .team:
            guard let value = try await APISportsStore.shared.team(id: route.identifier) else { throw LinkError.unavailable }
            return .team(value)
        case .player:
            guard let value = try await APISportsStore.shared.player(id: route.identifier) else { throw LinkError.unavailable }
            return .player(value)
        case .league:
            guard let value = LeagueOption.featured.first(where: { $0.apiFootballID == route.identifier || $0.id == route.identifier }) else { throw LinkError.unavailable }
            return .league(value)
        case .match:
            if let seed = APISportsStore.shared.today.first(where: { $0.id == route.identifier }) { return .match(seed) }
            if route.identifier.hasPrefix("np:") {
                let detail = try await CanonicalSportsClient.detail(matchID: route.identifier, date: route.kickoff)
                let match = detail.match.appMatch
                guard match.id == route.identifier else { throw LinkError.unavailable }
                return .match(match)
            }
            let result: APIEnvelope<[APIFixture]> = try await APIFootballClient.get("fixtures", query: [.init(name: "id", value: route.identifier)])
            guard let item = result.response.first(where: { String($0.fixture.id) == route.identifier }) else { throw LinkError.unavailable }
            return .match(APIPlusMatch(
                id: String(item.fixture.id), leagueID: item.league.id.map(String.init), league: item.league.name ?? "كرة القدم", leagueLogo: item.league.logo,
                homeID: item.teams.home.id.map(String.init), home: item.teams.home.name ?? "—", homeLogo: item.teams.home.logo,
                awayID: item.teams.away.id.map(String.init), away: item.teams.away.name ?? "—", awayLogo: item.teams.away.logo,
                homeScore: item.goals.home, awayScore: item.goals.away,
                date: item.fixture.date.flatMap { ISO8601DateFormatter().date(from: $0) },
                status: item.fixture.status.short ?? item.fixture.status.long ?? "", elapsed: item.fixture.status.elapsed))
        }
    }
}
