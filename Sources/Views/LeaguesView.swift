import SwiftUI

struct LeaguesView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    TopBar(title: "البطولات")
                    ForEach(LeagueOption.featured) { league in
                        NavigationLink {
                            StandingsView(league: league)
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14).fill(AppTheme.soft)
                                    Image(systemName: league.id == "4668" ? "trophy.fill" : "soccerball").foregroundStyle(AppTheme.green).font(.title2)
                                }
                                .frame(width: 54, height: 54)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(league.arabicName).font(.headline).foregroundStyle(.white)
                                    Text(league.englishName).font(.caption).foregroundStyle(AppTheme.muted)
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
                }.padding(.bottom, 30)
            }
            .background(AppTheme.bg.ignoresSafeArea())
        }
    }
}

struct StandingsView: View {
    let league: LeagueOption
    @State private var rows: [StandingRow] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 0) {
                header
                if loading {
                    ProgressView("جاري تحميل الترتيب...").tint(AppTheme.green).padding(40)
                } else if rows.isEmpty {
                    ContentUnavailableView("الترتيب غير متاح", systemImage: "tablecells", description: Text(error ?? "قد لا يدعم المصدر جدول هذه البطولة في الخطة المجانية."))
                        .frame(width: 380).padding(.top, 60)
                } else {
                    ForEach(rows) { row in standingRow(row) }
                }
            }
            .frame(minWidth: 390)
            .padding(.vertical, 10)
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .navigationTitle(league.arabicName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("#").frame(width: 28)
            Text("الفريق").frame(width: 150, alignment: .leading)
            Text("ل").frame(width: 28)
            Text("ف").frame(width: 28)
            Text("ت").frame(width: 28)
            Text("خ").frame(width: 28)
            Text("ن").frame(width: 40)
        }
        .font(.caption.bold()).foregroundStyle(AppTheme.muted)
        .padding(.horizontal, 12).padding(.vertical, 12)
        .background(AppTheme.card)
    }

    private func standingRow(_ row: StandingRow) -> some View {
        NavigationLink {
            if let id = row.idTeam { TeamDetailView(teamID: id, fallbackName: row.team) }
        } label: {
            HStack(spacing: 8) {
                Text("\(row.rank)").frame(width: 28).foregroundStyle(row.rank <= 4 ? AppTheme.green : .white)
                HStack(spacing: 8) {
                    RemoteBadge(url: row.strBadge).frame(width: 26, height: 26)
                    Text(row.team).lineLimit(1)
                }.frame(width: 150, alignment: .leading)
                Text("\(row.played)").frame(width: 28)
                Text("\(row.wins)").frame(width: 28)
                Text("\(row.draws)").frame(width: 28)
                Text("\(row.losses)").frame(width: 28)
                Text("\(row.points)").bold().frame(width: 40)
            }
            .font(.subheadline).foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 12)
            .background(row.rank % 2 == 0 ? AppTheme.soft : Color.clear)
        }
        .buttonStyle(.plain)
    }

    @MainActor private func load() async {
        loading = true; error = nil
        do { rows = try await FootballAPI.table(leagueID: league.id) }
        catch { self.error = "تعذر تحميل الترتيب الآن" }
        loading = false
    }
}

struct TeamDetailView: View {
    let teamID: String
    let fallbackName: String
    @State private var team: TeamProfile?
    @State private var loading = true
    @AppStorage("favoriteTeamIDs") private var favoriteTeamIDs = ""

    private var isFavorite: Bool {
        Set(favoriteTeamIDs.split(separator: ",").map(String.init)).contains(teamID)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if loading {
                    ProgressView("جاري تحميل النادي...").tint(AppTheme.green).padding(.top, 80)
                } else if let team {
                    hero(team)
                    info(team)
                } else {
                    ContentUnavailableView("تعذر تحميل النادي", systemImage: "shield.slash")
                }
            }.padding(16)
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .navigationTitle(team?.strTeam ?? fallbackName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: toggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star").foregroundStyle(AppTheme.green)
                }
            }
        }
        .task {
            do { team = try await FootballAPI.team(id: teamID) } catch { team = nil }
            loading = false
        }
    }

    private func hero(_ t: TeamProfile) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: t.strFanart1.flatMap(URL.init(string:))) { phase in
                if case .success(let image) = phase { image.resizable().scaledToFill() }
                else { LinearGradient(colors: [AppTheme.card, .black], startPoint: .top, endPoint: .bottom) }
            }
            .frame(height: 230).clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.95)], startPoint: .top, endPoint: .bottom)
            HStack(alignment: .bottom, spacing: 14) {
                RemoteBadge(url: t.strBadge).frame(width: 74, height: 74)
                VStack(alignment: .leading, spacing: 4) {
                    Text(t.strTeam ?? fallbackName).font(.title2.bold())
                    Text(t.strLeague ?? "كرة القدم").font(.caption).foregroundStyle(AppTheme.muted)
                }
            }.padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private func info(_ t: TeamProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let stadium = t.strStadium, !stadium.isEmpty { Label(stadium, systemImage: "sportscourt") }
            if let location = t.strLocation, !location.isEmpty { Label(location, systemImage: "mappin.and.ellipse") }
            if let year = t.intFormedYear, !year.isEmpty { Label("تأسس عام \(year)", systemImage: "calendar") }
            if let description = t.strDescriptionEN, !description.isEmpty {
                Divider().overlay(Color.white.opacity(0.1))
                Text(description).font(.subheadline).foregroundStyle(AppTheme.muted).lineLimit(8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private func toggleFavorite() {
        var ids = Set(favoriteTeamIDs.split(separator: ",").map(String.init))
        if ids.contains(teamID) { ids.remove(teamID) } else { ids.insert(teamID) }
        favoriteTeamIDs = ids.sorted().joined(separator: ",")
    }
}
