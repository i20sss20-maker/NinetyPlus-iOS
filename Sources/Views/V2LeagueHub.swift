import SwiftUI

extension LeagueOption {
    var apiFootballID: String {
        switch id {
        case "4668": return "307"   // Saudi Pro League
        case "4328": return "39"    // Premier League
        case "4335": return "140"   // La Liga
        case "4331": return "78"    // Bundesliga
        case "4332": return "135"   // Serie A
        case "4334": return "61"    // Ligue 1
        default: return id
        }
    }
}

struct V2LeagueHubView: View {
    let league: LeagueOption
    @State private var section = "الترتيب"
    @State private var standings: [APIPlusStanding] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                hero
                SegmentBar(items: ["الترتيب", "الفرق"], selected: $section)

                if loading {
                    ProgressView("جاري تحميل البطولة...")
                        .tint(AppTheme.green)
                        .padding(.top, 40)
                } else if standings.isEmpty {
                    ContentUnavailableView(
                        "بيانات البطولة غير متاحة",
                        systemImage: "trophy",
                        description: Text(error ?? "المصدر لم يرجع ترتيبًا لهذه البطولة حاليًا")
                    )
                    .padding(.top, 50)
                } else if section == "الفرق" {
                    teamsView
                } else {
                    standingsView
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
                Text("بيانات الترتيب من API-Football")
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

    private var standingsView: some View {
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

    private var teamsView: some View {
        LazyVStack(spacing: 10) {
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

    @MainActor
    private func load() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            standings = try await APISportsStore.shared.standings(leagueID: league.apiFootballID)
        } catch {
            standings = []
            self.error = "تعذر تحميل الترتيب الآن"
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
