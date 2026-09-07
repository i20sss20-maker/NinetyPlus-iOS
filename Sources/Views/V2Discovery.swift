import SwiftUI
import UIKit

struct V2DiscoverView: View {
    @State private var query = ""
    @State private var teams = PageResource<[APIPlusTeam]>()
    @State private var players = PageResource<[APIPlusPlayer]>()
    @State private var retry = 0
    private var entered: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var teamResults: [APIPlusTeam] { teams.key == entered ? (teams.value ?? []) : [] }
    private var playerResults: [APIPlusPlayer] { players.key == entered ? (players.value ?? []) : [] }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    TopBar(title: "البحث", subtitle: "الأندية واللاعبون")
                    if entered.count < 2 { introduction }
                    else {
                        PageLoadFeedback(loading: teams.isLoading || players.isLoading, hasValue: !teamResults.isEmpty || !playerResults.isEmpty,
                                         message: teams.errorMessage ?? players.errorMessage, updatedAt: nil) { retry += 1 }
                        if !teamResults.isEmpty {
                            section("الأندية", count: teamResults.count)
                            ForEach(teamResults) { team in
                                NavigationLink { V2TeamView(team: team) } label: { teamRow(team) }
                                    .buttonStyle(.plain).accessibilityIdentifier("search.team.\(team.id)")
                            }
                        }
                        if !playerResults.isEmpty {
                            section("اللاعبون", count: playerResults.count)
                            ForEach(playerResults) { player in
                                NavigationLink { V2PlayerView(player: player) } label: {
                                    profileRow(name: player.name, subtitle: SportsArabic.country(player.nationality) ?? "", image: player.photo)
                                }.buttonStyle(.plain).accessibilityIdentifier("search.player.\(player.id)")
                            }
                        }
                        if teams.value != nil, players.value != nil, !teams.isLoading, !players.isLoading,
                           teams.errorMessage == nil, players.errorMessage == nil, teamResults.isEmpty, playerResults.isEmpty {
                            ContentUnavailableView("لا توجد نتائج مطابقة", systemImage: "magnifyingglass", description: Text("جرّب جزءًا مختلفًا من الاسم أو تهجئته بالإنجليزية."))
                        }
                    }
                }.padding(.vertical, 10).padding(.bottom, 24)
            }
            .background(AppTheme.bg.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "مثال: الاتحاد، الهلال، رونالدو")
            .onSubmit(of: .search) { dismissKeyboard() }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("تم") { dismissKeyboard() }.accessibilityIdentifier("search.dismissKeyboard")
                }
            }
            .task(id: "\(entered):\(retry)") {
                let text = entered
                guard text.count >= 2 else { teams = PageResource(); players = PageResource(); return }
                do { try await Task.sleep(for: .milliseconds(380)); try Task.checkCancellation() } catch { return }
                async let a: Void = loadTeams(text)
                async let b: Void = loadPlayers(text)
                _ = await (a, b)
            }
            .onDisappear { teams.invalidate(); players.invalidate() }
        }
    }
    @MainActor private func dismissKeyboard() { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
    private var introduction: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("فريقك ولاعبوك، أقرب إليك").font(.title3.bold())
            Text("ابحث عن النادي أو اللاعب، ثم افتح صفحته أو أضفه إلى متابعاتك.").font(.subheadline).foregroundStyle(AppTheme.muted)
            HStack(spacing: 8) {
                ForEach(["الاتحاد", "الهلال", "رونالدو"], id: \.self) { name in
                    Button(name) { query = name }.font(.caption.bold()).foregroundStyle(AppTheme.green)
                        .padding(10).background(AppTheme.green.opacity(0.10), in: Capsule())
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 22)).padding(.horizontal, 16)
    }
    private func providerText(_ text: String) -> String {
        let key = text.replacingOccurrences(of: "أ", with: "ا").replacingOccurrences(of: "إ", with: "ا").replacingOccurrences(of: "آ", with: "ا")
        let names = ["الاتحاد": "Ittihad", "الهلال": "Hilal", "النصر": "Nassr", "الاهلي": "Ahli", "الشباب": "Shabab", "القادسية": "Qadisiyah", "الاتفاق": "Ettifaq", "رونالدو": "Ronaldo", "كريستيانو": "Cristiano Ronaldo", "ميسي": "Messi", "نيمار": "Neymar"]
        return names[key] ?? text
    }
    @MainActor private func loadTeams(_ text: String) async {
        guard !Task.isCancelled else { return }
        let token = teams.begin(key: text)
        defer { teams.cancel(token: token) }
        do {
            let values = try await APISportsStore.shared.searchTeams(providerText(text))
            try Task.checkCancellation()
            if entered == text { teams.succeed(values, token: token) }
        } catch {
            if !Task.isCancelled && !(error is CancellationError) && entered == text { teams.fail(error.localizedDescription, token: token) }
        }
    }
    @MainActor private func loadPlayers(_ text: String) async {
        guard !Task.isCancelled else { return }
        let token = players.begin(key: text)
        defer { players.cancel(token: token) }
        do {
            let values = try await APISportsStore.shared.searchPlayers(providerText(text))
            try Task.checkCancellation()
            if entered == text { players.succeed(values, token: token) }
        } catch {
            if !Task.isCancelled && !(error is CancellationError) && entered == text { players.fail(error.localizedDescription, token: token) }
        }
    }
    private func section(_ title: String, count: Int) -> some View {
        HStack { Text(title).font(.title3.bold()); Spacer(); Text("\(count) نتيجة").font(.caption).foregroundStyle(AppTheme.muted) }.padding(.horizontal, 20)
    }
    private func teamRow(_ team: APIPlusTeam) -> some View {
        profileRow(name: SportsArabic.team(team.name), subtitle: [SportsArabic.country(team.country), ClubPresentation.city(team.city)].compactMap { $0 }.joined(separator: " • "), image: team.logo)
    }
    private func profileRow(name: String, subtitle: String, image: String?) -> some View {
        HStack(spacing: 13) {
            RemoteBadge(url: image).frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 6) {
                Text(name).font(.headline).foregroundStyle(.white)
                if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(AppTheme.muted).lineLimit(2) }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.left").font(.caption.bold()).foregroundStyle(AppTheme.muted)
        }.padding(15).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 20)).padding(.horizontal, 16)
    }
}

private enum ClubPresentation {
    static func city(_ name: String?) -> String? {
        guard let name else { return nil }
        return ["Jeddah": "جدة", "Riyadh": "الرياض", "Dammam": "الدمام", "Mecca": "مكة المكرمة", "Medina": "المدينة المنورة", "Alexandria": "الإسكندرية", "Cairo": "القاهرة", "Aleppo": "حلب", "Tripoli": "طرابلس"][name] ?? name
    }
}

struct V2TeamView: View {
    let team: APIPlusTeam
    @State private var upcoming = PageResource<[APIPlusMatch]>()
    @State private var recent = PageResource<[APIPlusMatch]>()
    @State private var retry = 0
    @AppStorage("favoriteTeamIDs") private var favoriteTeamIDs = ""
    private var followed: Bool { SavedFavoriteIDs.parse(favoriteTeamIDs).contains(team.id) }
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        RemoteBadge(url: team.logo).frame(width: 86, height: 86)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(SportsArabic.team(team.name)).font(.title2.bold())
                            Text([SportsArabic.country(team.country), ClubPresentation.city(team.city)].compactMap { $0 }.joined(separator: " • ")).font(.caption).foregroundStyle(AppTheme.muted)
                            if let founded = team.founded { Text("تأسس عام \(String(founded))").font(.caption).foregroundStyle(AppTheme.muted) }
                        }
                        Spacer(minLength: 0)
                    }
                    if let venue = team.venue { Label(venue, systemImage: "sportscourt").font(.caption).foregroundStyle(AppTheme.muted) }
                    Button(action: toggleFollow) {
                        Label(followed ? "متابَع" : "متابعة النادي", systemImage: followed ? "star.fill" : "star")
                            .font(.subheadline.bold()).foregroundStyle(followed ? .black : AppTheme.green).padding(.horizontal, 18).padding(.vertical, 10)
                            .background(followed ? AppTheme.green : AppTheme.green.opacity(0.1), in: Capsule())
                    }.accessibilityIdentifier("team.follow")
                }.padding(20).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 24)).padding(.horizontal, 16)
                matchSection("الأيام السبعة القادمة", state: upcoming)
                matchSection("نتائج الأيام السبعة الماضية", state: recent)
            }.padding(.vertical, 14)
        }.background(AppTheme.bg.ignoresSafeArea()).navigationTitle(SportsArabic.team(team.name)).navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .task(id: "\(team.id):\(retry)") { await load() }.refreshable { await load() }
            .onDisappear { upcoming.invalidate(); recent.invalidate() }
    }
    private func matchSection(_ title: String, state: PageResource<[APIPlusMatch]>) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20)
            PageLoadFeedback(loading: state.isLoading || state.key == nil, hasValue: state.value != nil, message: state.errorMessage, updatedAt: nil) { retry += 1 }
            ForEach(state.value ?? []) { match in
                NavigationLink { V2MatchCenterView(match: match) } label: { APICompactMatchCard(match: match) }.buttonStyle(.plain)
            }
            if let items = state.value, items.isEmpty, !state.isLoading, state.errorMessage == nil {
                Text("لا توجد مباريات منشورة ضمن هذه الفترة.").font(.caption).foregroundStyle(AppTheme.muted).padding(20)
            }
        }
    }
    @MainActor private func load() async {
        async let a: Void = loadPart(next: true)
        async let b: Void = loadPart(next: false)
        _ = await (a, b)
    }
    @MainActor private func loadPart(next: Bool) async {
        guard !Task.isCancelled else { return }
        let token = next ? upcoming.begin(key: team.id) : recent.begin(key: team.id)
        defer { if next { upcoming.cancel(token: token) } else { recent.cancel(token: token) } }
        do {
            let values = try await APISportsStore.shared.teamFixtures(teamID: team.id, next: next)
            try Task.checkCancellation()
            if next { upcoming.succeed(values, token: token) } else { recent.succeed(values, token: token) }
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            if next { upcoming.fail(error.localizedDescription, token: token) } else { recent.fail(error.localizedDescription, token: token) }
        }
    }
    private func toggleFollow() {
        var ids = Set(SavedFavoriteIDs.parse(favoriteTeamIDs))
        if followed { ids.remove(team.id) } else { ids.insert(team.id) }
        favoriteTeamIDs = ids.sorted().joined(separator: ",")
    }
}

struct V2PlayerView: View {
    let player: APIPlusPlayer
    @AppStorage("favoritePlayerIDs") private var favoritePlayerIDs = ""
    @State private var resource = PageResource<[APIPlusPlayerSeasonStat]>()
    @State private var retry = 0
    private var followed: Bool { SavedFavoriteIDs.parse(favoritePlayerIDs).contains(player.id) }
    private var displayedSeason: Int { resource.value?.first?.season ?? APIFootballClient.currentSeason }
    private var isPreviousSeason: Bool { resource.value?.first.map { $0.season != APIFootballClient.currentSeason } ?? false }
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 14) {
                    RemoteBadge(url: player.photo).frame(width: 112, height: 112)
                    Text(player.name).font(.title2.bold()).multilineTextAlignment(.center).accessibilityIdentifier("player.name")
                    Button(action: toggleFollow) {
                        Label(followed ? "متابَع" : "متابعة اللاعب", systemImage: followed ? "star.fill" : "star")
                            .font(.subheadline.bold()).foregroundStyle(AppTheme.green).padding(12).background(AppTheme.green.opacity(0.1), in: Capsule())
                    }
                }.frame(maxWidth: .infinity).padding(20).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 24))
                VStack(spacing: 14) {
                    info("الجنسية", SportsArabic.country(player.nationality))
                    info("تاريخ الميلاد", SportsCopy.birthDate(player.birth))
                    info("الطول", player.height?.replacingOccurrences(of: "cm", with: "سم"))
                    info("الوزن", player.weight?.replacingOccurrences(of: "kg", with: "كجم"))
                }.padding(18).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20))
                VStack(alignment: .leading, spacing: 5) {
                    Text("إحصائيات موسم \(SeasonCopy.label(displayedSeason))").font(.headline)
                    if isPreviousSeason {
                        Text("المصدر لم يوفّر إحصائيات الموسم الحالي؛ هذه آخر إحصائيات متاحة وموسمها موضح أعلاه.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                PageLoadFeedback(loading: resource.isLoading || resource.key == nil, hasValue: resource.value != nil, message: resource.errorMessage, updatedAt: nil) { retry += 1 }
                ForEach(resource.value ?? []) { stat in
                    VStack(spacing: 14) {
                        HStack(spacing: 10) {
                            RemoteBadge(url: stat.teamLogo).frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(SportsArabic.team(stat.team)).font(.headline)
                                Text(SportsArabic.league(stat.league)).font(.caption).foregroundStyle(AppTheme.muted)
                            }
                            Spacer()
                        }
                        HStack {
                            metric("مباريات", stat.appearances); metric("دقائق", stat.minutes)
                            metric("أهداف", stat.goals); metric("صناعة أهداف", stat.assists)
                        }
                    }.padding(16).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 20))
                }
                if resource.value?.isEmpty == true, !resource.isLoading, resource.errorMessage == nil {
                    Text("لم ينشر المصدر إحصائيات متاحة للاعب في الموسمين اللذين تم فحصهما.").font(.caption).foregroundStyle(AppTheme.muted).padding(20)
                }
            }.padding(16)
        }.background(AppTheme.bg.ignoresSafeArea()).navigationTitle("اللاعب").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .task(id: "\(player.id):\(retry)") { await load() }.refreshable { await load() }.onDisappear { resource.invalidate() }
    }
    private func metric(_ title: String, _ value: Int?) -> some View {
        VStack(spacing: 5) { Text(SportsCopy.metric(value)).font(.headline.bold()); Text(title).font(.caption2).foregroundStyle(AppTheme.muted) }.frame(maxWidth: .infinity)
    }
    private func info(_ title: String, _ value: String?) -> some View {
        HStack { Text(title).foregroundStyle(AppTheme.muted); Spacer(); Text(value?.isEmpty == false ? value! : "غير متاح").fontWeight(.semibold) }.font(.subheadline)
    }
    @MainActor private func load() async {
        guard !Task.isCancelled else { return }
        let token = resource.begin(key: player.id)
        defer { resource.cancel(token: token) }
        do {
            let values = try await APISportsStore.shared.playerSeasonStats(playerID: player.id)
            try Task.checkCancellation(); resource.succeed(values, token: token)
        } catch {
            if !Task.isCancelled && !(error is CancellationError) { resource.fail(error.localizedDescription, token: token) }
        }
    }
    private func toggleFollow() {
        var ids = Set(SavedFavoriteIDs.parse(favoritePlayerIDs))
        if followed { ids.remove(player.id) } else { ids.insert(player.id) }
        favoritePlayerIDs = ids.sorted().joined(separator: ",")
    }
}
