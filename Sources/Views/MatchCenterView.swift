import SwiftUI

struct MatchCenterView: View {
    let match: LiveMatch
    @StateObject private var insight = MatchInsightStore()
    @State private var tab = "نظرة"
    @State private var homeRecent: [TeamEvent] = []
    @State private var awayRecent: [TeamEvent] = []
    @State private var h2h: [TeamEvent] = []
    @State private var extraLoading = false
    @AppStorage("followedMatchIDs") private var followedMatchIDs = ""

    private var followed: Bool {
        Set(followedMatchIDs.split(separator: ",").map(String.init)).contains(match.id)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                SegmentBar(items: ["نظرة", "الإحصائيات", "الأحداث", "التشكيلة", "H2H"], selected: $tab)
                if insight.loading || extraLoading {
                    ProgressView("جاري تحميل تفاصيل المباراة...").tint(AppTheme.green).padding(.vertical, 20)
                }
                switch tab {
                case "الإحصائيات": statsSection
                case "الأحداث": timelineSection
                case "التشكيلة": lineupSection
                case "H2H": h2hSection
                default: overviewSection
                }
            }.padding(.vertical, 12)
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .navigationTitle("مركز المباراة")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: toggleFollow) {
                    Image(systemName: followed ? "bell.fill" : "bell").foregroundStyle(AppTheme.green)
                }
            }
        }
        .task {
            await insight.load(eventID: match.id)
            await loadFormAndH2H()
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack {
                Text(match.league).font(.caption.bold()).foregroundStyle(AppTheme.muted)
                Spacer()
                Text(statusText).font(.caption.bold()).foregroundStyle(isLive ? AppTheme.green : AppTheme.muted)
            }
            HStack(spacing: 14) {
                club(match.home, match.homeBadge)
                Spacer()
                VStack(spacing: 5) {
                    if let h = match.homeScore, let a = match.awayScore {
                        Text("\(h) - \(a)").font(.system(size: 40, weight: .black))
                    } else {
                        Text(match.time).font(.title2.bold()).foregroundStyle(AppTheme.green)
                    }
                    if isLive { Text("مباشر").font(.caption.bold()).foregroundStyle(AppTheme.green) }
                }
                Spacer()
                club(match.away, match.awayBadge)
            }
        }
        .padding(18)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(isLive ? AppTheme.green.opacity(0.45) : .clear, lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private var overviewSection: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                summaryChip("الحالة", statusText, "clock.fill")
                summaryChip("النتيجة", scoreText, "sportscourt.fill")
            }.padding(.horizontal, 16)
            formCard(match.home, events: homeRecent)
            formCard(match.away, events: awayRecent)
            if !h2h.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("آخر المواجهات").font(.headline)
                    ForEach(h2h.prefix(3)) { event in compactEvent(event) }
                }
                .padding(16)
                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 16)
            }
        }
    }

    private var statsSection: some View {
        VStack(spacing: 0) {
            if insight.stats.isEmpty { unavailable("لا توجد إحصائيات منشورة لهذه المباراة") }
            else {
                ForEach(insight.stats) { stat in
                    HStack {
                        Text(stat.home).bold().frame(width: 55, alignment: .leading)
                        Spacer()
                        Text(arabicStat(stat.name)).font(.caption).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
                        Spacer()
                        Text(stat.away).bold().frame(width: 55, alignment: .trailing)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    Divider().overlay(Color.white.opacity(0.08))
                }
            }
        }
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 16)
    }

    private var timelineSection: some View {
        VStack(spacing: 0) {
            if insight.timeline.isEmpty { unavailable("لا توجد أحداث تفصيلية منشورة لهذه المباراة") }
            else {
                ForEach(insight.timeline) { event in
                    HStack(spacing: 12) {
                        Text("\(event.intTime ?? "-")′").font(.headline).foregroundStyle(AppTheme.green).frame(width: 42)
                        Image(systemName: timelineIcon(event.strTimeline ?? "")).foregroundStyle(AppTheme.green)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.strPlayer ?? event.strTeam ?? "حدث").font(.subheadline.bold())
                            Text(event.strTimelineDetail ?? event.strComment ?? event.strTimeline ?? "").font(.caption).foregroundStyle(AppTheme.muted)
                        }
                        Spacer()
                    }.padding(14)
                    Divider().overlay(Color.white.opacity(0.08))
                }
            }
        }
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 16)
    }

    private var lineupSection: some View {
        VStack(spacing: 14) {
            if insight.lineup.isEmpty { unavailable("التشكيلة غير متاحة من المصدر لهذه المباراة") }
            else {
                lineupTeam(match.home, home: true)
                lineupTeam(match.away, home: false)
            }
        }.padding(.horizontal, 16)
    }

    private var h2hSection: some View {
        VStack(spacing: 12) {
            if h2h.isEmpty { unavailable("لا توجد مواجهات سابقة متاحة من المصدر") }
            else { ForEach(h2h.prefix(8)) { event in compactEvent(event) } }
        }.padding(.horizontal, 16)
    }

    private func summaryChip(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon).foregroundStyle(AppTheme.green)
            Text(value).font(.headline).lineLimit(1)
            Text(title).font(.caption2).foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private func formCard(_ teamName: String, events: [TeamEvent]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("فورمة \(teamName)").font(.headline); Spacer(); Text("آخر 5").font(.caption).foregroundStyle(AppTheme.muted) }
            if events.isEmpty { Text("غير متاحة من المصدر").font(.caption).foregroundStyle(AppTheme.muted) }
            else {
                HStack(spacing: 8) {
                    ForEach(Array(events.prefix(5))) { event in
                        let result = formLetter(event, teamName: teamName)
                        Text(result).font(.caption.bold())
                            .foregroundStyle(result == "ف" ? .black : .white)
                            .frame(width: 32, height: 32)
                            .background(formColor(result), in: Circle())
                    }
                    Spacer()
                }
            }
        }
        .padding(16).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
    }

    private func compactEvent(_ event: TeamEvent) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(event.strHomeTeam ?? "—").font(.subheadline.bold()).lineLimit(1)
                Text(event.strAwayTeam ?? "—").font(.subheadline.bold()).lineLimit(1)
            }
            Spacer()
            if let h = event.intHomeScore, let a = event.intAwayScore { Text("\(h) - \(a)").font(.headline) }
            else { Text(String((event.strTime ?? "—").prefix(5))).font(.headline).foregroundStyle(AppTheme.green) }
            Text(event.dateEvent ?? "").font(.caption2).foregroundStyle(AppTheme.muted)
        }
        .padding(13).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private func lineupTeam(_ title: String, home: Bool) -> some View {
        let players = insight.lineup.filter { ($0.strHome == "Yes") == home }
        return VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundStyle(AppTheme.green)
            ForEach(players) { player in
                HStack(spacing: 10) {
                    AsyncImage(url: (player.strCutout ?? player.strThumb).flatMap(URL.init(string:))) { phase in
                        if case .success(let image) = phase { image.resizable().scaledToFit() }
                        else { Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(AppTheme.soft) }
                    }.frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.strPlayer ?? "لاعب").font(.subheadline.bold())
                        Text("\(player.intSquadNumber ?? "-") • \(player.strPosition ?? "")\(player.strSubstitute == "Yes" ? " • بديل" : "")")
                            .font(.caption).foregroundStyle(AppTheme.muted)
                    }
                    Spacer()
                }
            }
        }.padding(16).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private func unavailable(_ text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "info.circle").font(.title2).foregroundStyle(AppTheme.green)
            Text(text).font(.subheadline).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(28).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private func club(_ name: String, _ badge: String?) -> some View {
        VStack(spacing: 7) {
            RemoteBadge(url: badge).frame(width: 62, height: 62)
            Text(name).font(.headline).multilineTextAlignment(.center).lineLimit(2).frame(maxWidth: 108)
        }
    }

    @MainActor private func loadFormAndH2H() async {
        extraLoading = true
        let homeTeams = (try? await FootballAPI.searchTeams(match.home)) ?? []
        let awayTeams = (try? await FootballAPI.searchTeams(match.away)) ?? []
        let homeID = exactTeamID(in: homeTeams, name: match.home)
        let awayID = exactTeamID(in: awayTeams, name: match.away)
        if let homeID { homeRecent = (try? await FootballAPI.lastEvents(teamID: homeID)) ?? [] }
        if let awayID { awayRecent = (try? await FootballAPI.lastEvents(teamID: awayID)) ?? [] }
        h2h = homeRecent.filter { event in
            let h = event.strHomeTeam ?? ""
            let a = event.strAwayTeam ?? ""
            return (h.localizedCaseInsensitiveContains(match.home) && a.localizedCaseInsensitiveContains(match.away)) ||
                   (h.localizedCaseInsensitiveContains(match.away) && a.localizedCaseInsensitiveContains(match.home))
        }
        extraLoading = false
    }

    private func exactTeamID(in teams: [TeamProfile], name: String) -> String? {
        teams.first(where: { ($0.strTeam ?? "").localizedCaseInsensitiveCompare(name) == .orderedSame })?.idTeam ?? teams.first?.idTeam
    }

    private func toggleFollow() {
        var ids = Set(followedMatchIDs.split(separator: ",").map(String.init))
        if ids.contains(match.id) { ids.remove(match.id) } else { ids.insert(match.id) }
        followedMatchIDs = ids.sorted().joined(separator: ",")
    }

    private var isLive: Bool {
        let s = match.status.lowercased()
        return s.contains("live") || s.contains("1h") || s.contains("2h") || s.contains("half") || s.contains("in progress") || s == "ht"
    }

    private var statusText: String {
        let s = match.status.lowercased()
        if isLive { return "مباشر" }
        if s.contains("finished") || s == "ft" { return "انتهت" }
        if s.contains("postpon") { return "مؤجلة" }
        if s.contains("cancel") { return "ملغاة" }
        return match.status.isEmpty ? "مجدولة" : match.status
    }

    private var scoreText: String {
        if let h = match.homeScore, let a = match.awayScore { return "\(h)-\(a)" }
        return "—"
    }

    private func formLetter(_ event: TeamEvent, teamName: String) -> String {
        guard let h = Int(event.intHomeScore ?? ""), let a = Int(event.intAwayScore ?? "") else { return "-" }
        let isHome = (event.strHomeTeam ?? "").localizedCaseInsensitiveContains(teamName)
        let teamScore = isHome ? h : a
        let opponent = isHome ? a : h
        if teamScore > opponent { return "ف" }
        if teamScore < opponent { return "خ" }
        return "ت"
    }

    private func formColor(_ result: String) -> Color {
        switch result {
        case "ف": return AppTheme.green
        case "خ": return Color.red.opacity(0.8)
        case "ت": return Color.gray.opacity(0.7)
        default: return AppTheme.soft
        }
    }

    private func arabicStat(_ value: String) -> String {
        let map = ["Shots on Goal":"تسديدات على المرمى", "Shots off Goal":"تسديدات خارج المرمى", "Total Shots":"إجمالي التسديدات", "Blocked Shots":"تسديدات محجوبة", "Possession":"الاستحواذ", "Corners":"الركنيات", "Fouls":"الأخطاء", "Yellow Cards":"بطاقات صفراء", "Red Cards":"بطاقات حمراء", "Passes":"التمريرات"]
        return map[value] ?? value
    }

    private func timelineIcon(_ type: String) -> String {
        let t = type.lowercased()
        if t.contains("goal") { return "soccerball" }
        if t.contains("card") { return "rectangle.fill" }
        if t.contains("subst") { return "arrow.left.arrow.right" }
        return "circle.fill"
    }
}
