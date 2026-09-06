import SwiftUI

struct LeagueHubView: View {
    let league: LeagueOption
    @State private var section = "الترتيب"
    @State private var standings: [StandingRow] = []
    @State private var recent: [TeamEvent] = []
    @State private var upcoming: [TeamEvent] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                hero
                SegmentBar(items: ["الترتيب", "المباريات", "الفرق"], selected: $section)
                if loading {
                    ProgressView("جاري تحميل البطولة...").tint(AppTheme.green).padding(.top, 40)
                } else {
                    switch section {
                    case "المباريات": matchesSection
                    case "الفرق": teamsSection
                    default: standingsSection
                    }
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
                RoundedRectangle(cornerRadius: 20).fill(AppTheme.soft)
                Image(systemName: "trophy.fill").font(.system(size: 34, weight: .bold)).foregroundStyle(AppTheme.green)
            }.frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 5) {
                Text(league.arabicName).font(.title2.bold())
                Text(league.englishName).font(.caption).foregroundStyle(AppTheme.muted)
                Text("ترتيب • نتائج • مباريات قادمة • فرق").font(.caption2).foregroundStyle(AppTheme.green)
            }
            Spacer()
        }
        .padding(18)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var standingsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("#").frame(width: 28)
                    Text("الفريق").frame(width: 155, alignment: .leading)
                    Text("ل").frame(width: 28)
                    Text("ف").frame(width: 28)
                    Text("ت").frame(width: 28)
                    Text("خ").frame(width: 28)
                    Text("ن").frame(width: 40)
                }
                .font(.caption.bold()).foregroundStyle(AppTheme.muted)
                .padding(.horizontal, 12).padding(.vertical, 12)
                .background(AppTheme.card)

                if standings.isEmpty {
                    empty("الترتيب غير متاح من المصدر حاليًا", icon: "tablecells")
                } else {
                    ForEach(standings) { row in
                        NavigationLink {
                            if let id = row.idTeam { TeamDetailView(teamID: id, fallbackName: row.team) }
                        } label: {
                            HStack(spacing: 8) {
                                Text("\(row.rank)").frame(width: 28).foregroundStyle(row.rank <= 4 ? AppTheme.green : .white)
                                HStack(spacing: 8) {
                                    RemoteBadge(url: row.strBadge).frame(width: 28, height: 28)
                                    Text(row.team).lineLimit(1)
                                }.frame(width: 155, alignment: .leading)
                                Text("\(row.played)").frame(width: 28)
                                Text("\(row.wins)").frame(width: 28)
                                Text("\(row.draws)").frame(width: 28)
                                Text("\(row.losses)").frame(width: 28)
                                Text("\(row.points)").bold().frame(width: 40)
                            }
                            .font(.subheadline).foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 12)
                            .background(row.rank % 2 == 0 ? AppTheme.soft : Color.clear)
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(minWidth: 400)
        }
    }

    private var matchesSection: some View {
        VStack(spacing: 18) {
            matchGroup(title: "المباريات القادمة", events: upcoming)
            matchGroup(title: "آخر النتائج", events: recent)
        }
    }

    private var teamsSection: some View {
        LazyVStack(spacing: 10) {
            if standings.isEmpty {
                empty("قائمة الفرق غير متاحة", icon: "shield")
            } else {
                ForEach(standings) { row in
                    if let id = row.idTeam {
                        NavigationLink { TeamDetailView(teamID: id, fallbackName: row.team) } label: {
                            HStack(spacing: 12) {
                                RemoteBadge(url: row.strBadge).frame(width: 46, height: 46)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.team).font(.headline).foregroundStyle(.white)
                                    Text("المركز \(row.rank) • \(row.points) نقطة").font(.caption).foregroundStyle(AppTheme.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.left").foregroundStyle(AppTheme.muted)
                            }
                            .padding(14)
                            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
                            .padding(.horizontal, 16)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func matchGroup(title: String, events: [TeamEvent]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(title).font(.headline); Spacer(); Text("\(events.count)").font(.caption).foregroundStyle(AppTheme.green) }
                .padding(.horizontal, 16)
            if events.isEmpty {
                empty("لا توجد بيانات متاحة", icon: "calendar")
            } else {
                ForEach(events.prefix(12)) { event in eventCard(event) }
            }
        }
    }

    private func eventCard(_ event: TeamEvent) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text(event.dateEvent ?? "").font(.caption2).foregroundStyle(AppTheme.muted)
                Spacer()
                if let status = event.strStatus, !status.isEmpty { Text(status).font(.caption2).foregroundStyle(AppTheme.green) }
            }
            HStack(spacing: 10) {
                team(event.strHomeTeam ?? "—", event.strHomeTeamBadge)
                Spacer()
                VStack(spacing: 3) {
                    if let hs = event.intHomeScore, let ascore = event.intAwayScore {
                        Text("\(hs) - \(ascore)").font(.title3.bold())
                    } else {
                        Text(String((event.strTime ?? "—").prefix(5))).font(.headline).foregroundStyle(AppTheme.green)
                    }
                }
                Spacer()
                team(event.strAwayTeam ?? "—", event.strAwayTeamBadge)
            }
        }
        .padding(14)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 16)
    }

    private func team(_ name: String, _ badge: String?) -> some View {
        VStack(spacing: 5) {
            RemoteBadge(url: badge).frame(width: 38, height: 38)
            Text(name).font(.caption.bold()).multilineTextAlignment(.center).lineLimit(2).frame(maxWidth: 95)
        }
    }

    private func empty(_ text: String, icon: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.title2).foregroundStyle(AppTheme.green)
            Text(text).font(.subheadline).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(30)
    }

    @MainActor private func load() async {
        loading = true
        async let s = try? FootballAPI.table(leagueID: league.id)
        async let r = try? FootballAPI.lastLeagueEvents(leagueID: league.id)
        async let u = try? FootballAPI.nextLeagueEvents(leagueID: league.id)
        let values = await (s, r, u)
        standings = values.0 ?? []
        recent = values.1 ?? []
        upcoming = values.2 ?? []
        loading = false
    }
}
