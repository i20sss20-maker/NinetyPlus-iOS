import SwiftUI
import UIKit

@MainActor final class PremiumGlobalSearchStore: ObservableObject {
    @Published var teams = PageResource<[APIPlusTeam]>()
    @Published var players = PageResource<[APIPlusPlayer]>()
    @Published var retry = 0

    func search(_ raw: String) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else { teams = PageResource(); players = PageResource(); return }
        do { try await Task.sleep(for: .milliseconds(320)); try Task.checkCancellation() } catch { return }
        async let a: Void = loadTeams(text)
        async let b: Void = loadPlayers(text)
        _ = await (a, b)
    }
    func cancel() { teams.invalidate(); players.invalidate() }
    private func provider(_ text: String) -> String {
        let key = text.replacingOccurrences(of: "أ", with: "ا").replacingOccurrences(of: "إ", with: "ا").replacingOccurrences(of: "آ", with: "ا")
        return ["الاتحاد":"Ittihad", "الهلال":"Hilal", "النصر":"Nassr", "الاهلي":"Ahli", "رونالدو":"Ronaldo", "ميسي":"Messi", "نيمار":"Neymar"][key] ?? text
    }
    private func loadTeams(_ text: String) async {
        let token = teams.begin(key: text); defer { teams.cancel(token: token) }
        do {
            let values = try await APISportsStore.shared.searchTeams(provider(text)); try Task.checkCancellation()
            teams.succeed(values, token: token)
        } catch { if !Task.isCancelled && !(error is CancellationError) { teams.fail(error.localizedDescription, token: token) } }
    }
    private func loadPlayers(_ text: String) async {
        let token = players.begin(key: text); defer { players.cancel(token: token) }
        do {
            let values = try await APISportsStore.shared.searchPlayers(provider(text)); try Task.checkCancellation()
            players.succeed(values, token: token)
        } catch { if !Task.isCancelled && !(error is CancellationError) { players.fail(error.localizedDescription, token: token) } }
    }
}

struct PremiumGlobalSearch: View {
    @StateObject private var store = PremiumGlobalSearchStore()
    @StateObject private var editorial = EditorialStore.shared
    @StateObject private var premium = PremiumFootballStore.shared
    @State private var query = ""
    @State private var scope = "الكل"
    private var entered: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var leagues: [LeagueOption] {
        guard entered.count >= 2 else { return [] }
        return LeagueOption.featured.filter { [SportsArabic.league($0.name), $0.name].contains { $0.localizedCaseInsensitiveContains(entered) } }
    }
    private var matches: [PulseFixture] {
        guard entered.count >= 2 else { return [] }
        return premium.archive.latest.values.filter { [$0.home, $0.away, $0.league].contains { $0.localizedCaseInsensitiveContains(entered) } }.prefix(20).map { $0 }
    }
    private var articles: [PremiumArticle] {
        guard entered.count >= 2 else { return [] }
        return (editorial.news + editorial.transfers).compactMap(\.premiumArticle).filter { $0.title.localizedCaseInsensitiveContains(entered) }.prefix(20).map { $0 }
    }
    private func visible(_ name: String) -> Bool { scope == "الكل" || scope == name }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                TopBar(title: "البحث الشامل", subtitle: "لاعب • نادي • بطولة • مباراة • خبر")
                Picker("نوع النتيجة", selection: $scope) {
                    ForEach(["الكل", "الأندية", "اللاعبون", "البطولات", "المباريات", "الأخبار"], id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.menu).padding(.horizontal, 16)

                if entered.count < 2 {
                    ContentUnavailableView("ابدأ بحرفين على الأقل", systemImage: "magnifyingglass", description: Text("البحث في الأندية واللاعبين يحتاج اتصالًا؛ المباريات المحفوظة والأخبار المستلمة يمكن العثور عليها من النسخة المحلية."))
                } else {
                    PageLoadFeedback(loading: store.teams.isLoading || store.players.isLoading,
                                     hasValue: store.teams.value != nil || store.players.value != nil,
                                     message: store.teams.errorMessage ?? store.players.errorMessage,
                                     updatedAt: nil) { store.retry += 1 }
                    if visible("الأندية") { teamSection }
                    if visible("اللاعبون") { playerSection }
                    if visible("البطولات") { leagueSection }
                    if visible("المباريات") { matchSection }
                    if visible("الأخبار") { newsSection }
                }
            }.padding(.vertical, 12).padding(.bottom, 28)
        }
        .background(AppTheme.bg.ignoresSafeArea()).navigationTitle("بحث شامل").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "مثال: الاتحاد أو Ronaldo")
        .task(id: "\(entered)|\(store.retry)") { await store.search(entered) }
        .task { await editorial.refreshIfStale(maxAge: 300) }
        .onDisappear { store.cancel() }
        .accessibilityIdentifier("premium.globalSearch")
    }

    @ViewBuilder private var teamSection: some View {
        if let values = store.teams.value, !values.isEmpty {
            header("الأندية", count: values.count)
            ForEach(values.prefix(15)) { team in
                NavigationLink { V2TeamView(team: team) } label: {
                    resultRow(SportsArabic.team(team.name), subtitle: SportsArabic.country(team.country) ?? "", icon: "shield.fill")
                }.buttonStyle(.plain)
            }
        }
    }
    @ViewBuilder private var playerSection: some View {
        if let values = store.players.value, !values.isEmpty {
            header("اللاعبون", count: values.count)
            ForEach(values.prefix(15)) { player in
                NavigationLink { V2PlayerView(player: player) } label: {
                    resultRow(player.name, subtitle: SportsArabic.country(player.nationality) ?? "", icon: "person.fill")
                }.buttonStyle(.plain)
            }
        }
    }
    @ViewBuilder private var leagueSection: some View {
        if !leagues.isEmpty {
            header("البطولات", count: leagues.count)
            ForEach(leagues) { league in
                NavigationLink { V2LeagueHubView(league: league) } label: { resultRow(SportsArabic.league(league.name), subtitle: "بطولة", icon: "trophy.fill") }.buttonStyle(.plain)
            }
        }
    }
    @ViewBuilder private var matchSection: some View {
        if !matches.isEmpty {
            header("المباريات المحفوظة", count: matches.count)
            ForEach(matches) { match in
                NavigationLink { V2MatchCenterView(match: match.appMatch) } label: { PremiumMatchCard(match: match, spoiler: UserDefaults.standard.bool(forKey: V2PreferenceKey.spoilerMode)) }.buttonStyle(.plain)
            }
        }
    }
    @ViewBuilder private var newsSection: some View {
        if !articles.isEmpty {
            header("الأخبار", count: articles.count)
            ForEach(articles) { article in
                VStack(alignment: .leading, spacing: 8) {
                    Text(article.title).font(.headline)
                    Text(article.source).font(.caption).foregroundStyle(AppTheme.muted)
                    if let url = PremiumArticle.safeURL(article.url) { InAppWebLink(url: url) { Label("فتح المصدر", systemImage: "safari") }.foregroundStyle(AppTheme.green) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(15).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
            }
        }
    }
    private func header(_ title: String, count: Int) -> some View {
        HStack { Text(title).font(.title3.bold()); Spacer(); Text(String(count)).font(.caption).foregroundStyle(AppTheme.muted) }.padding(.horizontal, 18)
    }
    private func resultRow(_ title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(AppTheme.green).frame(width: 32)
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(AppTheme.muted) } }
            Spacer(); Image(systemName: "chevron.left").font(.caption).foregroundStyle(AppTheme.muted)
        }.foregroundStyle(.white).padding(15).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
    }
}
