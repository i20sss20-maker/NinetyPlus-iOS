import SwiftUI
import UserNotifications

struct MoreView: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("favoriteLeague") private var favoriteLeague = "الدوري السعودي"
    @AppStorage("favoriteTeamIDs") private var favoriteTeamIDs = ""
    @State private var notificationStatus = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        BrandLogo()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("كل كرة القدم في مكان واحد").font(.headline)
                            Text("مباريات، أخبار، انتقالات، بطولات ولاعبون").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 6)
                }
                Section("استكشف") {
                    NavigationLink { DiscoverView() } label: { Label("البحث عن الأندية واللاعبين", systemImage: "magnifyingglass") }
                    NavigationLink { LeaguesView() } label: { Label("البطولات والترتيب", systemImage: "trophy.fill") }
                    NavigationLink { FavoriteTeamsView() } label: {
                        HStack { Label("الفرق المفضلة", systemImage: "star.fill"); Spacer(); Text("\(favoriteCount)").foregroundStyle(.secondary) }
                    }
                }
                Section("التفضيلات") {
                    Toggle("السماح بالإشعارات", isOn: Binding(get: { notificationsEnabled }, set: { value in
                        notificationsEnabled = value
                        if value { Task { await requestNotifications() } }
                    }))
                    if !notificationStatus.isEmpty { Text(notificationStatus).font(.caption).foregroundStyle(.secondary) }
                    Picker("الدوري المفضل", selection: $favoriteLeague) {
                        ForEach(LeagueOption.featured) { league in Text(league.arabicName).tag(league.arabicName) }
                    }
                }
                Section("حالة البيانات") {
                    Label("المباريات والبطولات: بيانات مباشرة", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Label("الأخبار والانتقالات: مصادر فعلية", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("إذا لم ينشر مزود البيانات معلومة مثل التشكيلة أو الإحصائية فلن يعرض التطبيق بيانات تقديرية أو مختلقة.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("عن التطبيق") {
                    HStack { Text("الإصدار"); Spacer(); Text("1.0 RC").foregroundStyle(.secondary) }
                    Text("90+ مصمم للآيفون بواجهة عربية RTL وهوية داكنة وخضراء.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.bg)
            .navigationTitle("المزيد")
        }
    }

    private var favoriteCount: Int { favoriteTeamIDs.split(separator: ",").count }

    @MainActor private func requestNotifications() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            notificationStatus = granted ? "تم السماح بالإشعارات" : "الإشعارات غير مسموحة من إعدادات iOS"
            if !granted { notificationsEnabled = false }
        } catch {
            notificationStatus = "تعذر طلب إذن الإشعارات"
            notificationsEnabled = false
        }
    }
}

struct DiscoverView: View {
    @State private var query = ""
    @State private var teams: [TeamProfile] = []
    @State private var players: [PlayerProfile] = []
    @State private var loading = false
    @State private var message = "ابحث باسم نادي أو لاعب"

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if loading { ProgressView("جاري البحث...").tint(AppTheme.green).padding(.top, 30) }
                if !teams.isEmpty {
                    sectionTitle("الأندية")
                    ForEach(teams) { team in
                        if let id = team.idTeam {
                            NavigationLink { TeamDetailView(teamID: id, fallbackName: team.strTeam ?? "نادي") } label: { teamRow(team) }.buttonStyle(.plain)
                        }
                    }
                }
                if !players.isEmpty {
                    sectionTitle("اللاعبون")
                    ForEach(players) { player in
                        NavigationLink { PlayerDetailView(player: player) } label: { playerRow(player) }.buttonStyle(.plain)
                    }
                }
                if !loading && teams.isEmpty && players.isEmpty {
                    ContentUnavailableView(message, systemImage: "magnifyingglass").foregroundStyle(.white).padding(.top, 80)
                }
            }.padding(.bottom, 30)
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .navigationTitle("بحث")
        .searchable(text: $query, prompt: "مثال: الهلال أو Cristiano Ronaldo")
        .onSubmit(of: .search) { Task { await search() } }
    }

    @MainActor private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else { message = "اكتب حرفين على الأقل"; return }
        loading = true; teams = []; players = []
        async let t = try? FootballAPI.searchTeams(text)
        async let p = try? FootballAPI.searchPlayers(text)
        let values = await (t, p)
        teams = values.0 ?? []
        players = (values.1 ?? []).filter { ($0.strSport ?? "Soccer") == "Soccer" }
        message = (teams.isEmpty && players.isEmpty) ? "لا توجد نتائج لهذا البحث" : ""
        loading = false
    }

    private func sectionTitle(_ text: String) -> some View { HStack { Text(text).font(.title3.bold()); Spacer() }.padding(.horizontal, 16) }

    private func teamRow(_ t: TeamProfile) -> some View {
        HStack(spacing: 12) {
            RemoteBadge(url: t.strBadge).frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(t.strTeam ?? "نادي").font(.headline).foregroundStyle(.white)
                Text(t.strLeague ?? t.strLocation ?? "").font(.caption).foregroundStyle(AppTheme.muted)
            }
            Spacer(); Image(systemName: "chevron.left").foregroundStyle(AppTheme.muted)
        }.padding(14).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
    }

    private func playerRow(_ p: PlayerProfile) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: (p.strCutout ?? p.strThumb).flatMap(URL.init(string:))) { phase in
                if case .success(let image) = phase { image.resizable().scaledToFill() }
                else { Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(AppTheme.green.opacity(0.7)) }
            }.frame(width: 52, height: 52).clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(p.strPlayer ?? "لاعب").font(.headline).foregroundStyle(.white)
                Text([p.strTeam, p.strPosition].compactMap { $0 }.joined(separator: " • ")).font(.caption).foregroundStyle(AppTheme.muted)
            }
            Spacer(); Image(systemName: "chevron.left").foregroundStyle(AppTheme.muted)
        }.padding(14).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
    }
}

struct PlayerDetailView: View {
    let player: PlayerProfile
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ZStack(alignment: .bottomLeading) {
                    AsyncImage(url: (player.strBanner ?? player.strThumb).flatMap(URL.init(string:))) { phase in
                        if case .success(let img) = phase { img.resizable().scaledToFill() }
                        else { LinearGradient(colors: [AppTheme.card, .black], startPoint: .top, endPoint: .bottom) }
                    }.frame(height: 250).clipped()
                    LinearGradient(colors: [.clear, .black.opacity(0.95)], startPoint: .top, endPoint: .bottom)
                    HStack(alignment: .bottom, spacing: 14) {
                        AsyncImage(url: (player.strCutout ?? player.strThumb).flatMap(URL.init(string:))) { phase in
                            if case .success(let img) = phase { img.resizable().scaledToFit() }
                            else { Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(AppTheme.green.opacity(0.7)) }
                        }.frame(width: 84, height: 84)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(player.strPlayer ?? "لاعب").font(.title2.bold())
                            Text(player.strTeam ?? "").font(.caption).foregroundStyle(AppTheme.muted)
                        }
                    }.padding(16)
                }.clipShape(RoundedRectangle(cornerRadius: 22))
                VStack(alignment: .leading, spacing: 12) {
                    detail("المركز", player.strPosition)
                    detail("الجنسية", player.strNationality)
                    detail("رقم القميص", player.strNumber)
                    detail("الطول", player.strHeight)
                    detail("الوزن", player.strWeight)
                    detail("تاريخ الميلاد", player.dateBorn)
                    if let desc = player.strDescriptionEN, !desc.isEmpty {
                        Divider().overlay(Color.white.opacity(0.1))
                        Text(desc).font(.subheadline).foregroundStyle(AppTheme.muted).lineLimit(10)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
            }.padding(16)
        }.background(AppTheme.bg.ignoresSafeArea()).navigationTitle(player.strPlayer ?? "اللاعب").navigationBarTitleDisplayMode(.inline)
    }

    private func detail(_ title: String, _ value: String?) -> some View {
        Group { if let value, !value.isEmpty { HStack { Text(title).foregroundStyle(AppTheme.muted); Spacer(); Text(value).bold() } } }
    }
}

struct FavoriteTeamsView: View {
    @AppStorage("favoriteTeamIDs") private var favoriteTeamIDs = ""
    @State private var teams: [TeamProfile] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if loading { ProgressView("جاري تحميل المفضلة...").tint(AppTheme.green).padding(.top, 60) }
                else if teams.isEmpty { ContentUnavailableView("لا توجد فرق مفضلة", systemImage: "star", description: Text("أضف فريقًا للمفضلة من صفحة النادي.")).padding(.top, 60) }
                else {
                    ForEach(teams) { team in
                        if let id = team.idTeam {
                            NavigationLink { TeamDetailView(teamID: id, fallbackName: team.strTeam ?? "نادي") } label: {
                                HStack(spacing: 12) {
                                    RemoteBadge(url: team.strBadge).frame(width: 48, height: 48)
                                    VStack(alignment: .leading) { Text(team.strTeam ?? "نادي").font(.headline); Text(team.strLeague ?? "").font(.caption).foregroundStyle(AppTheme.muted) }
                                    Spacer(); Image(systemName: "chevron.left").foregroundStyle(AppTheme.muted)
                                }.foregroundStyle(.white).padding(14).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }.background(AppTheme.bg.ignoresSafeArea()).navigationTitle("الفرق المفضلة").task { await load() }
    }

    @MainActor private func load() async {
        let ids = favoriteTeamIDs.split(separator: ",").map(String.init)
        var loaded: [TeamProfile] = []
        for id in ids.prefix(20) {
            do {
                if let team = try await FootballAPI.team(id: id) { loaded.append(team) }
            } catch { }
        }
        teams = loaded
        loading = false
    }
}
