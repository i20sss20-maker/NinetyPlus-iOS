import SwiftUI

extension LeagueOption {
    var apiFootballID: String {
        switch id {
        case "4668": return "307"
        case "4328": return "39"
        case "4335": return "140"
        case "4331": return "78"
        case "4332": return "135"
        case "4334": return "61"
        default: return id
        }
    }
}

struct V2LeagueHubView: View {
    let league: LeagueOption
    @State private var section = "الترتيب"
    @State private var standingsState = PageResource<[APIPlusStanding]>()
    @State private var matchesState = PageResource<[APIPlusMatch]>()
    @State private var scorersState = PageResource<[APIPlusScorer]>()
    @State private var retryID = 0

    private var rootKey: String { "\(league.apiFootballID):\(APIFootballClient.currentSeason)" }
    private var sectionKind: String {
        switch section {
        case "المباريات": return "matches"
        case "الهدافون": return "scorers"
        default: return "standings"
        }
    }
    private var activeKey: String { "\(rootKey):\(sectionKind)" }
    private var standings: [APIPlusStanding] { standingsState.key == "\(rootKey):standings" ? (standingsState.value ?? []) : [] }
    private var matches: [APIPlusMatch] { matchesState.key == "\(rootKey):matches" ? (matchesState.value ?? []) : [] }
    private var scorers: [APIPlusScorer] { scorersState.key == "\(rootKey):scorers" ? (scorersState.value ?? []) : [] }
    private var mayShowEmpty: Bool {
        switch sectionKind {
        case "matches": return isEmptySuccess(matchesState)
        case "scorers": return isEmptySuccess(scorersState)
        default: return isEmptySuccess(standingsState)
        }
    }
    private func isEmptySuccess<T>(_ state: PageResource<T>) -> Bool {
        state.key == activeKey && state.value != nil && !state.isLoading && state.errorMessage == nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                hero
                SegmentBar(items: ["الترتيب", "المباريات", "الهدافون", "الفرق"], selected: $section)
                switch sectionKind {
                case "matches": feedback(matchesState)
                case "scorers": feedback(scorersState)
                default: feedback(standingsState)
                }
                content
            }.padding(.bottom, 28)
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .navigationTitle(league.arabicName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(activeKey)|\(retryID)") { await loadActive() }
        .refreshable { await loadActive(force: true) }
        .onDisappear {
            standingsState.invalidate(); matchesState.invalidate(); scorersState.invalidate()
        }
    }

    private func feedback<T>(_ state: PageResource<T>) -> some View {
        PageLoadFeedback(
            loading: state.isLoading || state.key != activeKey,
            hasValue: state.key == activeKey && state.value != nil,
            message: state.key == activeKey ? state.errorMessage : nil,
            updatedAt: state.key == activeKey ? state.lastUpdated : nil
        ) { retryID += 1 }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [AppTheme.cardRaised, AppTheme.greenDeep.opacity(0.52)], startPoint: .topTrailing, endPoint: .bottomLeading))
            Circle()
                .fill(AppTheme.green.opacity(0.08))
                .frame(width: 180, height: 180)
                .offset(x: -48, y: 65)
            HStack(spacing: 15) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(AppTheme.green)
                }.frame(width: 78, height: 78)
                VStack(alignment: .leading, spacing: 6) {
                    Text(league.arabicName)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(league.englishName)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(1)
                    HStack(spacing: 7) {
                        Label("\(APIFootballClient.currentSeason)", systemImage: "calendar")
                        Text("•")
                        Text("بيانات مباشرة")
                    }
                    .font(.caption2.bold())
                    .foregroundStyle(AppTheme.green)
                }
                Spacer(minLength: 0)
            }
            .padding(19)
        }
        .frame(minHeight: 126)
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(AppTheme.border, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder private var content: some View {
        switch section {
        case "المباريات": matchesView
        case "الهدافون": scorersView
        case "الفرق": teamsView
        default: standingsView
        }
    }

    private var standingsView: some View {
        Group {
            if standings.isEmpty {
                if mayShowEmpty { empty("الترتيب غير متاح من المصدر حاليًا", icon: "tablecells") }
            } else {
                VStack(spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("جدول الترتيب").font(.headline)
                            Text("ل = لعب • ف = فوز • ت = تعادل • خ = خسارة").font(.caption2).foregroundStyle(AppTheme.muted)
                        }
                        Spacer()
                        Text("ن = نقاط").font(.caption2.bold()).foregroundStyle(AppTheme.green)
                    }
                    .padding(.horizontal, 16)

                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(spacing: 0) {
                            HStack(spacing: 8) {
                                Text("#").frame(width: 30)
                                Text("الفريق").frame(width: 174, alignment: .leading)
                                Text("ل").frame(width: 30)
                                Text("ف").frame(width: 30)
                                Text("ت").frame(width: 30)
                                Text("خ").frame(width: 30)
                                Text("+/-").frame(width: 40)
                                Text("ن").frame(width: 42)
                            }
                            .font(.caption.bold()).foregroundStyle(AppTheme.muted)
                            .padding(.horizontal, 12).padding(.vertical, 12)
                            .background(AppTheme.cardRaised)

                            ForEach(standings) { row in
                                HStack(spacing: 8) {
                                    ZStack {
                                        Circle().fill(rankColor(row.rank).opacity(row.rank <= 4 ? 0.15 : 0.06))
                                        Text("\(row.rank)").font(.caption.bold()).foregroundStyle(rankColor(row.rank))
                                    }.frame(width: 30, height: 30)
                                    HStack(spacing: 8) {
                                        RemoteBadge(url: row.logo).frame(width: 30, height: 30)
                                        Text(SportsArabic.team(row.team)).lineLimit(1)
                                    }.frame(width: 174, alignment: .leading)
                                    Text("\(row.played)").frame(width: 30)
                                    Text("\(row.win)").frame(width: 30)
                                    Text("\(row.draw)").frame(width: 30)
                                    Text("\(row.lose)").frame(width: 30)
                                    Text(row.goalDifference > 0 ? "+\(row.goalDifference)" : "\(row.goalDifference)")
                                        .frame(width: 40)
                                        .foregroundStyle(row.goalDifference > 0 ? AppTheme.green : (row.goalDifference < 0 ? .orange : AppTheme.muted))
                                    Text("\(row.points)").fontWeight(.bold).frame(width: 42)
                                }
                                .font(.subheadline).foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .background(row.rank % 2 == 0 ? AppTheme.soft : Color.clear)
                            }
                        }
                        .frame(minWidth: 454)
                        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppTheme.border, lineWidth: 1))
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    private func rankColor(_ rank: Int) -> Color {
        if rank <= 4 { return AppTheme.green }
        return .white
    }

    private var matchesView: some View {
        LazyVStack(spacing: 10) {
            if matches.isEmpty {
                if mayShowEmpty { empty("مباريات البطولة غير متاحة حاليًا", icon: "calendar") }
            } else {
                HStack {
                    Text("آخر المباريات والقادمة").font(.headline)
                    Spacer()
                    Text("\(matches.count)").font(.caption.bold()).foregroundStyle(AppTheme.green)
                }.padding(.horizontal, 16)
                ForEach(matches) { match in
                    NavigationLink { V2MatchCenterView(match: match) } label: {
                        APICompactMatchCard(match: match)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var scorersView: some View {
        LazyVStack(spacing: 10) {
            if scorers.isEmpty {
                if mayShowEmpty { empty("قائمة الهدافين غير متاحة من المصدر حاليًا", icon: "figure.soccer") }
            } else {
                HStack {
                    Text("الهدافون").font(.headline)
                    Spacer()
                    Text("\(scorers.count) لاعب").font(.caption).foregroundStyle(AppTheme.muted)
                }.padding(.horizontal, 16)

                ForEach(scorers) { scorer in
                    NavigationLink {
                        V2PlayerLookupView(playerID: scorer.playerID, fallbackName: scorer.name, photo: scorer.photo)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(scorer.rank <= 3 ? AppTheme.green.opacity(0.15) : Color.white.opacity(0.05))
                                Text("\(scorer.rank)")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(scorer.rank <= 3 ? AppTheme.green : .white)
                            }.frame(width: 34, height: 34)
                            RemoteBadge(url: scorer.photo).frame(width: 56, height: 56)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(scorer.name).font(.headline).foregroundStyle(.white).lineLimit(1)
                                HStack(spacing: 6) {
                                    RemoteBadge(url: scorer.teamLogo).frame(width: 20, height: 20)
                                    Text(SportsArabic.team(scorer.team)).lineLimit(1)
                                    if let nationality = SportsArabic.country(scorer.nationality), !nationality.isEmpty {
                                        Text("•"); Text(nationality).lineLimit(1)
                                    }
                                }.font(.caption).foregroundStyle(AppTheme.muted)
                            }
                            Spacer(minLength: 4)
                            VStack(spacing: 2) {
                                Text("\(scorer.goals)").font(.system(size: 24, weight: .black, design: .rounded)).foregroundStyle(AppTheme.green)
                                Text("هدف").font(.caption2).foregroundStyle(AppTheme.muted)
                            }
                            .frame(minWidth: 42)
                        }
                        .padding(14)
                        .background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppTheme.border, lineWidth: 1))
                        .padding(.horizontal, 16)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var teamsView: some View {
        LazyVStack(spacing: 10) {
            if standings.isEmpty {
                if mayShowEmpty { empty("قائمة الفرق غير متاحة", icon: "shield") }
            } else {
                HStack {
                    Text("فرق البطولة").font(.headline)
                    Spacer()
                    Text("\(standings.count) فريق").font(.caption).foregroundStyle(AppTheme.muted)
                }.padding(.horizontal, 16)

                ForEach(standings) { row in
                    NavigationLink {
                        V2TeamLookupView(teamID: row.teamID, fallbackName: row.team, logo: row.logo)
                    } label: {
                        HStack(spacing: 13) {
                            RemoteBadge(url: row.logo).frame(width: 54, height: 54)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(SportsArabic.team(row.team)).font(.headline).foregroundStyle(.white)
                                HStack(spacing: 6) {
                                    Text("المركز \(row.rank)")
                                    Text("•")
                                    Text("\(row.points) نقطة")
                                    Text("•")
                                    Text("\(row.played) مباراة")
                                }.font(.caption).foregroundStyle(AppTheme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.left").font(.caption.bold()).foregroundStyle(AppTheme.dimmed)
                        }
                        .padding(14)
                        .background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppTheme.border, lineWidth: 1))
                        .padding(.horizontal, 16)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func empty(_ text: String, icon: String) -> some View {
        VStack(spacing: 11) {
            Image(systemName: icon).font(.system(size: 34, weight: .semibold)).foregroundStyle(AppTheme.green)
            Text(text).font(.subheadline).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppTheme.border, lineWidth: 1))
        .padding(.horizontal, 16)
    }

    @MainActor private func loadActive(force: Bool = false) async {
        guard !Task.isCancelled else { return }
        let key = activeKey
        let leagueID = league.apiFootballID
        switch sectionKind {
        case "matches":
            if !force && matchesState.isFresh(key: key, maxAge: 90) { return }
            let token = matchesState.begin(key: key)
            defer { matchesState.cancel(token: token) }
            do {
                let value = try await APISportsStore.shared.leagueFixtures(leagueID: leagueID)
                try Task.checkCancellation()
                guard activeKey == key else { return }
                matchesState.succeed(value, token: token)
            } catch {
                if !Task.isCancelled && !(error is CancellationError) && activeKey == key {
                    matchesState.fail(error.localizedDescription, token: token)
                }
            }
        case "scorers":
            if !force && scorersState.isFresh(key: key, maxAge: 180) { return }
            let token = scorersState.begin(key: key)
            defer { scorersState.cancel(token: token) }
            do {
                let value = try await APISportsStore.shared.topScorers(leagueID: leagueID)
                try Task.checkCancellation()
                guard activeKey == key else { return }
                scorersState.succeed(value, token: token)
            } catch {
                if !Task.isCancelled && !(error is CancellationError) && activeKey == key {
                    scorersState.fail(error.localizedDescription, token: token)
                }
            }
        default:
            if !force && standingsState.isFresh(key: key, maxAge: 180) { return }
            let token = standingsState.begin(key: key)
            defer { standingsState.cancel(token: token) }
            do {
                let value = try await APISportsStore.shared.standings(leagueID: leagueID)
                try Task.checkCancellation()
                guard activeKey == key else { return }
                standingsState.succeed(value, token: token)
            } catch {
                if !Task.isCancelled && !(error is CancellationError) && activeKey == key {
                    standingsState.fail(error.localizedDescription, token: token)
                }
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
            if resource.key == teamID, let team = resource.value ?? nil {
                V2TeamView(team: team)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        RemoteBadge(url: logo).frame(width: 76, height: 76)
                        Text(SportsArabic.team(fallbackName)).font(.headline)
                        PageLoadFeedback(loading: resource.isLoading || resource.key != teamID, hasValue: false, message: resource.errorMessage, updatedAt: nil) { retryID += 1 }
                        if resource.key == teamID && !resource.isLoading && resource.value != nil && resource.errorMessage == nil {
                            ContentUnavailableView("بيانات النادي غير متاحة من المصدر", systemImage: "shield")
                            Button("إعادة المحاولة") { retryID += 1 }.tint(AppTheme.green)
                        }
                    }.padding(.vertical, 24)
                }
            }
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .task(id: "\(teamID)|\(retryID)") { await load() }
        .onDisappear { resource.invalidate() }
    }

    @MainActor private func load() async {
        guard !Task.isCancelled else { return }
        let id = teamID
        let token = resource.begin(key: id)
        defer { resource.cancel(token: token) }
        do {
            let value = try await APISportsStore.shared.team(id: id)
            try Task.checkCancellation()
            guard teamID == id else { return }
            resource.succeed(value, token: token)
        } catch {
            if !Task.isCancelled && !(error is CancellationError) && teamID == id {
                resource.fail(error.localizedDescription, token: token)
            }
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
            if resource.key == playerID, let player = resource.value ?? nil {
                V2PlayerView(player: player)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        RemoteBadge(url: photo).frame(width: 80, height: 80)
                        Text(fallbackName).font(.headline)
                        PageLoadFeedback(loading: resource.isLoading || resource.key != playerID, hasValue: false, message: resource.errorMessage, updatedAt: nil) { retryID += 1 }
                        if resource.key == playerID && !resource.isLoading && resource.value != nil && resource.errorMessage == nil {
                            ContentUnavailableView("بيانات اللاعب غير متاحة من المصدر", systemImage: "person.crop.circle")
                            Button("إعادة المحاولة") { retryID += 1 }.tint(AppTheme.green)
                        }
                    }.padding(.vertical, 24)
                }
            }
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .task(id: "\(playerID)|\(retryID)") { await load() }
        .onDisappear { resource.invalidate() }
    }

    @MainActor private func load() async {
        guard !Task.isCancelled else { return }
        let id = playerID
        let token = resource.begin(key: id)
        defer { resource.cancel(token: token) }
        do {
            let value = try await APISportsStore.shared.player(id: id)
            try Task.checkCancellation()
            guard playerID == id else { return }
            resource.succeed(value, token: token)
        } catch {
            if !Task.isCancelled && !(error is CancellationError) && playerID == id {
                resource.fail(error.localizedDescription, token: token)
            }
        }
    }
}
