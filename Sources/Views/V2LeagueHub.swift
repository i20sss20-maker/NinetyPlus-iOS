import SwiftUI

struct V2LeagueHubView: View {
    let league: LeagueOption
    @State private var section = "الترتيب"
    @State private var matchesState = PageResource<[APIPlusMatch]>()
    @State private var scorersState = PageResource<[APIPlusScorer]>()
    @State private var retry = 0
    @State private var publicRefresh = 0
    private var key: String { "\(league.apiFootballID):\(section):\(APIFootballClient.currentSeason)" }
    private var matches: [APIPlusMatch] { matchesState.value ?? [] }
    private var scorers: [APIPlusScorer] { scorersState.value ?? [] }
    private var scorerSeason: Int { scorers.first?.season ?? APIFootballClient.currentSeason }
    private var scorerSeasonIsFallback: Bool { scorers.first.map { $0.season != APIFootballClient.currentSeason } ?? false }

    init(league: LeagueOption) {
        self.league = league
        _section = State(initialValue: PublicLeagueSource.code(for: league.apiFootballID) == nil ? "المباريات" : "الترتيب")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                SegmentBar(items: ["الترتيب", "المباريات", "الهدافون", "الفرق"], selected: $section)
                if section == "الترتيب" || section == "الفرق" {
                    if PublicLeagueSource.code(for: league.apiFootballID) != nil {
                        PublicLeagueTableView(league: league, teamsOnly: section == "الفرق", refreshID: publicRefresh)
                    } else {
                        ContentUnavailableView("جدول هذه البطولة غير متاح حاليًا", systemImage: "tablecells")
                    }
                } else if section == "المباريات" { matchesContent }
                else { scorersContent }
            }.padding(.vertical, 14).padding(.bottom, 24)
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .navigationTitle(league.arabicName).navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: "\(key):\(retry)") { await load() }
        .refreshable { publicRefresh += 1; await load(force: true) }
        .onDisappear { matchesState.invalidate(); scorersState.invalidate() }
    }
    private var header: some View {
        HStack(spacing: 16) {
            RemoteBadge(url: "https://media.api-sports.io/football/leagues/\(league.apiFootballID).png").frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 7) {
                Text(league.arabicName).font(.title2.bold()).foregroundStyle(.white)
                Text("الترتيب والنتائج وأندية البطولة").font(.caption).foregroundStyle(AppTheme.muted)
            }
            Spacer(minLength: 0)
        }.padding(20)
            .background(LinearGradient(colors: [AppTheme.cardRaised, AppTheme.greenDeep.opacity(0.22)], startPoint: .topTrailing, endPoint: .bottomLeading), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(AppTheme.border)).padding(.horizontal, 16)
    }
    private var matchesContent: some View {
        VStack(spacing: 12) {
            Text("مباريات الأسبوع الماضي والأيام السبعة القادمة")
                .font(.caption).foregroundStyle(AppTheme.muted).padding(.horizontal, 18)
            feedback(matchesState)
            ForEach(matches) { match in
                NavigationLink { V2MatchCenterView(match: match) } label: { APICompactMatchCard(match: match) }.buttonStyle(.plain)
            }
            if matchesState.value != nil, !matchesState.isLoading, matchesState.errorMessage == nil, matches.isEmpty {
                ContentUnavailableView("لا توجد مباريات ضمن هذه الفترة", systemImage: "calendar")
            }
        }
    }
    private var scorersContent: some View {
        VStack(spacing: 12) {
            Text("هدافو موسم \(SeasonCopy.label(scorerSeason))")
                .font(.caption).foregroundStyle(AppTheme.muted)
            if scorerSeasonIsFallback {
                Text("المصدر لم يوفّر قائمة الموسم الحالي؛ نعرض آخر موسم متاح مع توضيح موسمه.")
                    .font(.caption2).foregroundStyle(.orange).multilineTextAlignment(.center).padding(.horizontal, 20)
            }
            feedback(scorersState)
            ForEach(scorers) { scorer in
                NavigationLink { V2PlayerLookupView(playerID: scorer.playerID, fallbackName: scorer.name, photo: scorer.photo) } label: {
                    HStack(spacing: 12) {
                        Text(String(scorer.rank)).font(.caption.bold()).foregroundStyle(AppTheme.muted).frame(width: 24)
                        RemoteBadge(url: scorer.photo).frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(scorer.name).font(.subheadline.bold()).foregroundStyle(.white)
                            Text(SportsArabic.team(scorer.team)).font(.caption).foregroundStyle(AppTheme.muted)
                        }
                        Spacer()
                        VStack(spacing: 3) {
                            Text(String(scorer.goals)).font(.title2.bold()).foregroundStyle(AppTheme.green)
                            Text("أهداف").font(.caption2).foregroundStyle(AppTheme.muted)
                        }
                    }.padding(14).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
                }.buttonStyle(.plain)
            }
            if scorersState.value != nil, !scorersState.isLoading, scorersState.errorMessage == nil, scorers.isEmpty {
                ContentUnavailableView("قائمة الهدافين غير منشورة حاليًا", systemImage: "figure.soccer")
            }
            if scorersState.errorMessage != nil, let code = PublicLeagueSource.code(for: league.apiFootballID),
               let url = URL(string: "https://www.espn.com/soccer/stats/_/league/\(code)/view/scoring") {
                Link("عرض إحصائيات البطولة لدى ESPN", destination: url).font(.subheadline.bold()).foregroundStyle(AppTheme.green).padding(16)
            }
        }
    }
    private func feedback<T>(_ state: PageResource<T>) -> some View {
        PageLoadFeedback(loading: state.isLoading || state.key != key, hasValue: state.value != nil,
                         message: state.errorMessage, updatedAt: state.lastUpdated) { retry += 1 }
    }
    @MainActor private func load(force: Bool = false) async {
        guard !Task.isCancelled else { return }
        let activeKey = key
        if section == "المباريات" {
            if !force && matchesState.isFresh(key: key, maxAge: 300) { return }
            let token = matchesState.begin(key: key)
            defer { matchesState.cancel(token: token) }
            do {
                let value = try await APISportsStore.shared.leagueFixtures(leagueID: league.apiFootballID)
                try Task.checkCancellation()
                guard key == activeKey else { return }
                matchesState.succeed(value, token: token)
            } catch {
                if !Task.isCancelled && !(error is CancellationError) && key == activeKey { matchesState.fail(error.localizedDescription, token: token) }
            }
        } else if section == "الهدافون" {
            if !force && scorersState.isFresh(key: key, maxAge: 300) { return }
            let token = scorersState.begin(key: key)
            defer { scorersState.cancel(token: token) }
            do {
                let value = try await APISportsStore.shared.topScorers(leagueID: league.apiFootballID)
                try Task.checkCancellation()
                guard key == activeKey else { return }
                scorersState.succeed(value, token: token)
            } catch {
                if !Task.isCancelled && !(error is CancellationError) && key == activeKey { scorersState.fail(error.localizedDescription, token: token) }
            }
        }
    }
}

struct V2TeamLookupView: View {
    let teamID: String
    let fallbackName: String
    let logo: String?
    @State private var resource = PageResource<APIPlusTeam?>()
    @State private var retryID = 0
    var body: some View {
        Group {
            if resource.key == teamID, let team = resource.value ?? nil { V2TeamView(team: team) }
            else {
                ScrollView {
                    VStack(spacing: 16) {
                        RemoteBadge(url: logo).frame(width: 72, height: 72)
                        Text(SportsArabic.team(fallbackName)).font(.headline)
                        PageLoadFeedback(loading: resource.isLoading || resource.key != teamID, hasValue: false, message: resource.errorMessage, updatedAt: nil) { retryID += 1 }
                        if resource.key == teamID && !resource.isLoading && resource.value != nil && resource.errorMessage == nil {
                            ContentUnavailableView("بيانات النادي غير متاحة من المصدر", systemImage: "shield")
                            Button("إعادة المحاولة") { retryID += 1 }.tint(AppTheme.green)
                        }
                    }.padding(.vertical, 24)
                }
            }
        }.background(AppTheme.bg.ignoresSafeArea()).toolbar(.visible, for: .navigationBar)
            .task(id: "\(teamID)|\(retryID)") { await load() }.onDisappear { resource.invalidate() }
    }
    @MainActor private func load() async {
        guard !Task.isCancelled else { return }
        let id = teamID; let token = resource.begin(key: id)
        defer { resource.cancel(token: token) }
        do {
            let value = try await APISportsStore.shared.team(id: id)
            try Task.checkCancellation()
            if teamID == id { resource.succeed(value, token: token) }
        } catch {
            if !Task.isCancelled && !(error is CancellationError) && teamID == id { resource.fail(error.localizedDescription, token: token) }
        }
    }
}

struct V2PlayerLookupView: View {
    let playerID: String
    let fallbackName: String
    let photo: String?
    @State private var resource = PageResource<APIPlusPlayer?>()
    @State private var retryID = 0
    var body: some View {
        Group {
            if resource.key == playerID, let player = resource.value ?? nil { V2PlayerView(player: player) }
            else {
                ScrollView {
                    VStack(spacing: 16) {
                        RemoteBadge(url: photo).frame(width: 72, height: 72)
                        Text(fallbackName).font(.headline)
                        PageLoadFeedback(loading: resource.isLoading || resource.key != playerID, hasValue: false, message: resource.errorMessage, updatedAt: nil) { retryID += 1 }
                        if resource.key == playerID && !resource.isLoading && resource.value != nil && resource.errorMessage == nil {
                            ContentUnavailableView("بيانات اللاعب غير متاحة من المصدر", systemImage: "person.crop.circle")
                            Button("إعادة المحاولة") { retryID += 1 }.tint(AppTheme.green)
                        }
                    }.padding(.vertical, 24)
                }
            }
        }.background(AppTheme.bg.ignoresSafeArea()).toolbar(.visible, for: .navigationBar)
            .task(id: "\(playerID)|\(retryID)") { await load() }.onDisappear { resource.invalidate() }
    }
    @MainActor private func load() async {
        guard !Task.isCancelled else { return }
        let id = playerID; let token = resource.begin(key: id)
        defer { resource.cancel(token: token) }
        do {
            let value = try await APISportsStore.shared.player(id: id)
            try Task.checkCancellation()
            if playerID == id { resource.succeed(value, token: token) }
        } catch {
            if !Task.isCancelled && !(error is CancellationError) && playerID == id { resource.fail(error.localizedDescription, token: token) }
        }
    }
}
