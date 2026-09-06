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
    @State private var standings: [APIPlusStanding] = []
    @State private var matches: [APIPlusMatch] = []
    @State private var scorers: [APIPlusScorer] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                hero
                SegmentBar(items: ["الترتيب", "المباريات", "الهدافون", "الفرق"], selected: $section)

                if loading {
                    ProgressView("جاري تحميل البطولة...")
                        .tint(AppTheme.green)
                        .padding(.top, 40)
                } else {
                    content
                }
            }
            .padding(.bottom, 28)
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .navigationTitle(league.arabicName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var hero: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 20).fill(AppTheme.green.opacity(0.12))
                Image(systemName: "trophy.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(AppTheme.green)
            }
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 5) {
                Text(league.arabicName).font(.title2.bold())
                Text(league.englishName).font(.caption).foregroundStyle(AppTheme.muted)
                Text("ترتيب • مباريات • هدافون • فرق")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.green)
            }
            Spacer()
        }
        .padding(18)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case "المباريات":
            matchesView
        case "الهدافون":
            scorersView
        case "الفرق":
            teamsView
        default:
            standingsView
        }
    }

    private var standingsView: some View {
        Group {
            if standings.isEmpty {
                empty("الترتيب غير متاح من المصدر حاليًا", icon: "tablecells")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Text("#").frame(width: 28)
                            Text("الفريق").frame(width: 165, alignment: .leading)
                            Text("ل").frame(width: 28)
                            Text("ف").frame(width: 28)
                            Text("ت").frame(width: 28)
                            Text("خ").frame(width: 28)
                            Text("+/-").frame(width: 38)
                            Text("ن").frame(width: 40)
                        }
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(AppTheme.card)

                        ForEach(standings) { row in
                            HStack(spacing: 8) {
                                Text("\(row.rank)")
                                    .frame(width: 28)
                                    .foregroundStyle(row.rank <= 4 ? AppTheme.green : .white)
                                HStack(spacing: 8) {
                                    RemoteBadge(url: row.logo).frame(width: 28, height: 28)
                                    Text(row.team).lineLimit(1)
                                }
                                .frame(width: 165, alignment: .leading)
                                Text("\(row.played)").frame(width: 28)
                                Text("\(row.win)").frame(width: 28)
                                Text("\(row.draw)").frame(width: 28)
                                Text("\(row.lose)").frame(width: 28)
                                Text("\(row.goalDifference)").frame(width: 38)
                                Text("\(row.points)").bold().frame(width: 40)
                            }
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(row.rank % 2 == 0 ? AppTheme.soft : Color.clear)
                        }
                    }
                    .frame(minWidth: 430)
                }
            }
        }
    }

    private var matchesView: some View {
        LazyVStack(spacing: 10) {
            if matches.isEmpty {
                empty("مباريات البطولة غير متاحة حاليًا", icon: "calendar")
            } else {
                ForEach(matches) { match in
                    NavigationLink {
                        V2MatchCenterView(match: match)
                    } label: {
                        APICompactMatchCard(match: match)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var scorersView: some View {
        LazyVStack(spacing: 10) {
            if scorers.isEmpty {
                empty("قائمة الهدافين غير متاحة من المصدر حاليًا", icon: "figure.soccer")
            } else {
                ForEach(scorers) { scorer in
                    NavigationLink {
                        V2PlayerLookupView(playerID: scorer.playerID, fallbackName: scorer.name, photo: scorer.photo)
                    } label: {
                        HStack(spacing: 12) {
                            Text("\(scorer.rank)")
                                .font(.headline.bold())
                                .foregroundStyle(scorer.rank <= 3 ? AppTheme.green : .white)
                                .frame(width: 28)
                            RemoteBadge(url: scorer.photo).frame(width: 50, height: 50)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(scorer.name).font(.headline).foregroundStyle(.white)
                                HStack(spacing: 6) {
                                    RemoteBadge(url: scorer.teamLogo).frame(width: 18, height: 18)
                                    Text(scorer.team)
                                }
                                .font(.caption)
                                .foregroundStyle(AppTheme.muted)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("\(scorer.goals)")
                                    .font(.title3.bold())
                                    .foregroundStyle(AppTheme.green)
                                Text("هدف")
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.muted)
                            }
                        }
                        .padding(14)
                        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var teamsView: some View {
        LazyVStack(spacing: 10) {
            if standings.isEmpty {
                empty("قائمة الفرق غير متاحة", icon: "shield")
            } else {
                ForEach(standings) { row in
                    NavigationLink {
                        V2TeamLookupView(teamID: row.teamID, fallbackName: row.team, logo: row.logo)
                    } label: {
                        HStack(spacing: 12) {
                            RemoteBadge(url: row.logo).frame(width: 48, height: 48)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.team).font(.headline).foregroundStyle(.white)
                                Text("المركز \(row.rank) • \(row.points) نقطة")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.left").foregroundStyle(AppTheme.muted)
                        }
                        .padding(14)
                        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func empty(_ text: String, icon: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.title2).foregroundStyle(AppTheme.green)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
    }

    @MainActor
    private func load() async {
        loading = true
        error = nil
        defer { loading = false }

        async let standingsResult = try? APISportsStore.shared.standings(leagueID: league.apiFootballID)
        async let fixturesResult = try? APISportsStore.shared.leagueFixtures(leagueID: league.apiFootballID)
        async let scorersResult = try? APISportsStore.shared.topScorers(leagueID: league.apiFootballID)

        let result = await (standingsResult, fixturesResult, scorersResult)
        standings = result.0 ?? []
        matches = result.1 ?? []
        scorers = result.2 ?? []

        if standings.isEmpty && matches.isEmpty && scorers.isEmpty {
            error = "المصدر لم يرجع بيانات لهذه البطولة حاليًا"
        }
    }
}

struct V2TeamLookupView: View {
    let teamID: String
    let fallbackName: String
    let logo: String?
    @State private var team: APIPlusTeam?
    @State private var loading = true

    var body: some View {
        Group {
            if loading {
                ProgressView("جاري تحميل النادي...")
                    .tint(AppTheme.green)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.bg.ignoresSafeArea())
            } else if let team {
                V2TeamView(team: team)
            } else {
                ContentUnavailableView("تعذر تحميل النادي", systemImage: "shield.slash", description: Text(fallbackName))
                    .background(AppTheme.bg.ignoresSafeArea())
            }
        }
        .task {
            team = try? await APISportsStore.shared.team(id: teamID)
            loading = false
        }
    }
}

struct V2PlayerLookupView: View {
    let playerID: String
    let fallbackName: String
    let photo: String?
    @State private var player: APIPlusPlayer?
    @State private var loading = true

    var body: some View {
        Group {
            if loading {
                ProgressView("جاري تحميل اللاعب...")
                    .tint(AppTheme.green)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.bg.ignoresSafeArea())
            } else if let player {
                V2PlayerView(player: player)
            } else {
                ContentUnavailableView("تعذر تحميل اللاعب", systemImage: "person.crop.circle.badge.exclamationmark", description: Text(fallbackName))
                    .background(AppTheme.bg.ignoresSafeArea())
            }
        }
        .task {
            player = try? await APISportsStore.shared.player(id: playerID)
            loading = false
        }
    }
}
