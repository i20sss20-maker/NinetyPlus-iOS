import SwiftUI

struct LeaguesView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    TopBar(title: "البطولات")
                    ForEach(LeagueOption.featured) { league in
                        NavigationLink {
                            LeagueHubView(league: league)
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
    @State private var recent: [TeamEvent] = []
    @State private var upcoming: [TeamEvent] = []
    @State private var loading = true
    @State private var selectedSection = "نظرة عامة"
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
                    SegmentBar(items: ["نظرة عامة", "النتائج", "القادمة"], selected: $selectedSection)
                    switch selectedSection {
                    case "النتائج": eventList(recent, empty: "لا توجد نتائج حديثة متاحة")
                    case "القادمة": eventList(upcoming, empty: "لا توجد مباريات قادمة متاحة")
                    default:
                        formStrip
                        info(team)
                    }
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
        .task { await loadTeam() }
        .refreshable { await loadTeam() }
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

    private var formStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("آخر النتائج").font(.headline)
                Spacer()
                if !recent.isEmpty { Text("آخر \(min(recent.count, 5))").font(.caption).foregroundStyle(AppTheme.muted) }
            }
            if recent.isEmpty {
                Text("الفورمة غير متاحة من المصدر حاليًا").font(.caption).foregroundStyle(AppTheme.muted)
            } else {
                HStack(spacing: 8) {
                    ForEach(Array(recent.prefix(5))) { event in
                        Text(formLetter(event))
                            .font(.caption.bold())
                            .foregroundStyle(formColor(event) == AppTheme.green ? .black : .white)
                            .frame(width: 32, height: 32)
                            .background(formColor(event), in: Circle())
                    }
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private func info(_ t: TeamProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let stadium = t.strStadium, !stadium.isEmpty { Label(stadium, systemImage: "sportscourt") }
            if let location = t.strLocation, !location.isEmpty { Label(location, systemImage: "mappin.and.ellipse") }
            if let year = t.intFormedYear, !year.isEmpty { Label("تأسس عام \(year)", systemImage: "calendar") }
            if let website = t.strWebsite, !website.isEmpty,
               let url = URL(string: website.hasPrefix("http") ? website : "https://\(website)") {
                Link(destination: url) { Label("الموقع الرسمي", systemImage: "globe") }.foregroundStyle(AppTheme.green)
            }
            if let description = t.strDescriptionEN, !description.isEmpty {
                Divider().overlay(Color.white.opacity(0.1))
                Text(description).font(.subheadline).foregroundStyle(AppTheme.muted).lineLimit(8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private func eventList(_ events: [TeamEvent], empty: String) -> some View {
        VStack(spacing: 10) {
            if events.isEmpty {
                ContentUnavailableView(empty, systemImage: "calendar")
                    .frame(maxWidth: .infinity).padding(.vertical, 45)
            } else {
                ForEach(events) { event in eventCard(event) }
            }
        }
    }

    private func eventCard(_ event: TeamEvent) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text(event.strLeague ?? "كرة القدم").font(.caption).foregroundStyle(AppTheme.muted).lineLimit(1)
                Spacer()
                Text(eventDate(event)).font(.caption2).foregroundStyle(AppTheme.muted)
            }
            HStack(spacing: 12) {
                eventTeam(event.strHomeTeam ?? "—", event.strHomeTeamBadge)
                Spacer()
                VStack(spacing: 3) {
                    if let home = event.intHomeScore, let away = event.intAwayScore {
                        Text("\(home) - \(away)").font(.title3.bold())
                    } else {
                        Text(String((event.strTime ?? "—").prefix(5))).font(.headline).foregroundStyle(AppTheme.green)
                    }
                    if let status = event.strStatus, !status.isEmpty { Text(status).font(.caption2).foregroundStyle(AppTheme.muted) }
                }
                Spacer()
                eventTeam(event.strAwayTeam ?? "—", event.strAwayTeamBadge)
            }
        }
        .padding(14)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private func eventTeam(_ name: String, _ badge: String?) -> some View {
        VStack(spacing: 5) {
            RemoteBadge(url: badge).frame(width: 38, height: 38)
            Text(name).font(.caption.bold()).lineLimit(2).multilineTextAlignment(.center).frame(maxWidth: 92)
        }
    }

    @MainActor private func loadTeam() async {
        loading = true
        async let profile = try? FootballAPI.team(id: teamID)
        async let last = try? FootballAPI.lastEvents(teamID: teamID)
        async let next = try? FootballAPI.nextEvents(teamID: teamID)
        let values = await (profile, last, next)
        team = values.0 ?? nil
        recent = values.1 ?? []
        upcoming = values.2 ?? []
        loading = false
    }

    private func formLetter(_ event: TeamEvent) -> String {
        guard let hs = Int(event.intHomeScore ?? ""), let ascore = Int(event.intAwayScore ?? "") else { return "-" }
        let homeIsTeam = event.strHomeTeam?.localizedCaseInsensitiveContains(team?.strTeam ?? fallbackName) == true
        let teamScore = homeIsTeam ? hs : ascore
        let opponent = homeIsTeam ? ascore : hs
        if teamScore > opponent { return "ف" }
        if teamScore < opponent { return "خ" }
        return "ت"
    }

    private func formColor(_ event: TeamEvent) -> Color {
        switch formLetter(event) {
        case "ف": return AppTheme.green
        case "خ": return Color.red.opacity(0.8)
        case "ت": return Color.gray.opacity(0.7)
        default: return AppTheme.soft
        }
    }

    private func eventDate(_ event: TeamEvent) -> String {
        guard let raw = event.dateEvent else { return "" }
        let input = DateFormatter(); input.locale = Locale(identifier: "en_US_POSIX"); input.dateFormat = "yyyy-MM-dd"
        guard let date = input.date(from: raw) else { return raw }
        let output = DateFormatter(); output.locale = Locale(identifier: "ar_SA"); output.dateFormat = "d MMM"
        return output.string(from: date)
    }

    private func toggleFavorite() {
        var ids = Set(favoriteTeamIDs.split(separator: ",").map(String.init))
        if ids.contains(teamID) { ids.remove(teamID) } else { ids.insert(teamID) }
        favoriteTeamIDs = ids.sorted().joined(separator: ",")
    }
}
