import SwiftUI

struct V2PowerCenterView: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                TopBar(title: "90+ 2.0", subtitle: "أدوات وتحليلات وتجربة شخصية")
                NavigationLink { V2SaudiHubView() } label: { featureCard("كرة القدم السعودية", "دوري روشن والبطولات والمنتخب والمتابعات", "flag.fill") }
                NavigationLink { PlayerCompareView() } label: { featureCard("مقارنة اللاعبين", "قارن البيانات المنشورة للاعبين جنبًا إلى جنب", "person.2.fill") }
                NavigationLink { V2LineupBuilderView() } label: { featureCard("بناء التشكيلة", "كوّن تشكيلتك وشاركها مباشرة", "rectangle.3.group.fill") }
                NavigationLink { V2PowerSettingsView() } label: { featureCard("إعدادات 2.0", "Spoiler Mode والتنبيهات واستهلاك البيانات", "slider.horizontal.3") }
                dataTruthCard
            }.padding(.bottom, 30)
        }.background(AppTheme.bg.ignoresSafeArea())
    }

    private func featureCard(_ title: String, _ subtitle: String, _ icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(AppTheme.green)
                .frame(width: 50, height: 50).background(AppTheme.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(.white)
                Text(subtitle).font(.caption).foregroundStyle(AppTheme.muted).multilineTextAlignment(.leading)
            }
            Spacer(); Image(systemName: "chevron.left").foregroundStyle(AppTheme.muted)
        }.padding(14).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
    }

    private var dataTruthCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("سياسة البيانات", systemImage: "checkmark.shield.fill").foregroundStyle(AppTheme.green).font(.headline)
            Text("xG وخرائط التسديد والحرارة والإصابات والعقود وأماكن النقل تظهر فقط عندما يرسل المصدر بيانات موثوقة. 90+ لا يولد أرقامًا بديلة لملء الشاشة.")
                .font(.caption).foregroundStyle(AppTheme.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
    }
}

struct V2PowerSettingsView: View {
    @AppStorage(V2PreferenceKey.spoilerMode) private var spoilerMode = false
    @AppStorage(V2PreferenceKey.lowDataMode) private var lowDataMode = false
    @AppStorage(V2PreferenceKey.haptics) private var haptics = true
    @AppStorage(V2PreferenceKey.favoriteHomeMode) private var favoriteHomeMode = true
    @AppStorage(V2PreferenceKey.notifyKickoff) private var notifyKickoff = true
    @AppStorage(V2PreferenceKey.notifyGoals) private var notifyGoals = true
    @AppStorage(V2PreferenceKey.notifyLineups) private var notifyLineups = true
    @AppStorage(V2PreferenceKey.notifyRedCards) private var notifyRedCards = true
    @AppStorage(V2PreferenceKey.notifyTransfers) private var notifyTransfers = false
    @State private var notificationResult: Bool?
    @State private var calendarResult: Bool?

    var body: some View {
        Form {
            Section("العرض") {
                Toggle("إخفاء النتائج — Spoiler Mode", isOn: $spoilerMode)
                Toggle("الرئيسية حسب متابعاتي", isOn: $favoriteHomeMode)
                Toggle("اهتزازات خفيفة", isOn: $haptics)
                LabeledContent("الأرقام") { Text("0–9").monospacedDigit() }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("الأرقام الإنجليزية 0–9")
                    .accessibilityIdentifier("settings.digits")
            }
            Section("الأداء") {
                Toggle("Low Data Mode", isOn: $lowDataMode)
                Text("يقلل الصور والتحديثات غير الضرورية مع إبقاء النتائج والمباراة الأساسية.").font(.caption).foregroundStyle(.secondary)
            }
            Section("تنبيهات المباراة") {
                Toggle("بداية المباراة", isOn: $notifyKickoff)
                Toggle("الأهداف", isOn: $notifyGoals)
                Toggle("التشكيلة", isOn: $notifyLineups)
                Toggle("البطاقات الحمراء", isOn: $notifyRedCards)
                Toggle("الانتقالات", isOn: $notifyTransfers)
                Button("السماح بالتنبيهات") { Task { notificationResult = await V2Permissions.requestNotifications() } }
                if let notificationResult { Text(notificationResult ? "تم السماح" : "لم يتم السماح").font(.caption) }
            }
            Section("التقويم") {
                Button("السماح بإضافة المباريات للتقويم") { Task { calendarResult = await V2Permissions.requestCalendarAccess() } }
                if let calendarResult { Text(calendarResult ? "تم السماح" : "لم يتم السماح").font(.caption) }
            }
        }
        .scrollContentBackground(.hidden).background(AppTheme.bg)
        .navigationTitle("إعدادات 2.0").navigationBarTitleDisplayMode(.inline)
    }
}

struct V2SaudiHubView: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                TopBar(title: "السعودية", subtitle: "كرة القدم السعودية في مكان واحد")
                NavigationLink { V2LeaguesListView() } label: { hubCard("البطولات السعودية", "دوري روشن والكؤوس والبطولات الآسيوية", "trophy.fill") }
                NavigationLink { V2FavoritesView() } label: { hubCard("أنديتي", "مباريات وأخبار متابعاتك أولًا", "star.fill") }
                NavigationLink { V2DiscoverView() } label: { hubCard("الأندية واللاعبون", "ابحث عن أي نادي أو لاعب سعودي", "magnifyingglass") }
                NavigationLink { EnhancedNewsView() } label: { hubCard("آخر الأخبار", "أخبار الأندية والمنتخب من المصادر المنشورة", "newspaper.fill") }
            }.padding(.bottom, 30)
        }.background(AppTheme.bg.ignoresSafeArea())
    }
    private func hubCard(_ title: String, _ subtitle: String, _ icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).foregroundStyle(AppTheme.green).font(.title2).frame(width: 48, height: 48)
                .background(AppTheme.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(AppTheme.muted) }
            Spacer(); Image(systemName: "chevron.left").foregroundStyle(AppTheme.muted)
        }.foregroundStyle(.white).padding(14).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
    }
}

struct V2LineupBuilderView: View {
    @State private var formation = "4-3-3"
    @State private var names = Array(repeating: "", count: 11)
    private let formations = ["4-3-3", "4-2-3-1", "4-4-2", "3-5-2", "3-4-3"]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                TopBar(title: "بناء التشكيلة")
                Picker("الخطة", selection: $formation) { ForEach(formations, id: \.self) { Text($0).tag($0) } }
                    .pickerStyle(.segmented).padding(.horizontal, 16)
                VStack(spacing: 8) {
                    ForEach(0..<11, id: \.self) { index in
                        HStack {
                            Text(String(index + 1)).monospacedDigit().foregroundStyle(AppTheme.green).frame(width: 28)
                            TextField("اسم اللاعب", text: $names[index]).textInputAutocapitalization(.words)
                        }.padding(12).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 14))
                    }
                }.padding(.horizontal, 16)
                ShareLink(item: shareText) { Label("مشاركة التشكيلة", systemImage: "square.and.arrow.up").font(.headline).frame(maxWidth: .infinity).padding(14).background(AppTheme.green, in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(.black) }
                    .padding(.horizontal, 16)
            }.padding(.bottom, 30)
        }.background(AppTheme.bg.ignoresSafeArea()).navigationTitle("التشكيلة").navigationBarTitleDisplayMode(.inline)
    }

    private var shareText: String {
        let players = names.enumerated().map { "\($0.offset + 1). \($0.element.isEmpty ? "—" : $0.element)" }.joined(separator: "\n")
        return "90+ | \(formation)\n\(players)"
    }
}

struct PlayerCompareView: View {
    @State private var leftQuery = ""
    @State private var rightQuery = ""
    @State private var leftResults: [APIPlusPlayer] = []
    @State private var rightResults: [APIPlusPlayer] = []
    @State private var leftPlayer: APIPlusPlayer?
    @State private var rightPlayer: APIPlusPlayer?
    @State private var loadingLeft = false
    @State private var loadingRight = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                TopBar(title: "مقارنة اللاعبين")
                HStack(alignment: .top, spacing: 10) {
                    picker(title: "اللاعب الأول", query: $leftQuery, results: leftResults, selected: leftPlayer, loading: loadingLeft, side: true)
                    picker(title: "اللاعب الثاني", query: $rightQuery, results: rightResults, selected: rightPlayer, loading: loadingRight, side: false)
                }.padding(.horizontal, 16)
                if let leftPlayer, let rightPlayer {
                    VStack(spacing: 0) {
                        compare("الجنسية", leftPlayer.nationality, rightPlayer.nationality)
                        compare("تاريخ الميلاد", leftPlayer.birth, rightPlayer.birth)
                        compare("الطول", leftPlayer.height, rightPlayer.height)
                        compare("الوزن", leftPlayer.weight, rightPlayer.weight)
                    }.background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
                }
            }.padding(.bottom, 30)
        }.background(AppTheme.bg.ignoresSafeArea()).navigationTitle("مقارنة").navigationBarTitleDisplayMode(.inline)
    }

    private func picker(title: String, query: Binding<String>, results: [APIPlusPlayer], selected: APIPlusPlayer?, loading: Bool, side: Bool) -> some View {
        VStack(spacing: 9) {
            Text(title).font(.caption.bold()).foregroundStyle(AppTheme.muted)
            TextField("اسم اللاعب", text: query).textFieldStyle(.roundedBorder).submitLabel(.search)
                .onSubmit { Task { await search(text: query.wrappedValue, left: side) } }
            if loading { ProgressView().tint(AppTheme.green) }
            if let selected { mini(selected) }
            else { ForEach(results.prefix(5)) { player in Button { if side { leftPlayer = player; leftResults = [] } else { rightPlayer = player; rightResults = [] } } label: { HStack { RemoteBadge(url: player.photo).frame(width: 30, height: 30); Text(player.name).font(.caption.bold()).foregroundStyle(.white); Spacer() }.padding(8).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain) } }
        }.frame(maxWidth: .infinity)
    }
    private func mini(_ p: APIPlusPlayer) -> some View { VStack(spacing: 7) { RemoteBadge(url: p.photo).frame(width: 68, height: 68).clipShape(Circle()); Text(p.name).font(.subheadline.bold()).multilineTextAlignment(.center); Text(p.nationality ?? "").font(.caption2).foregroundStyle(AppTheme.muted) }.frame(maxWidth: .infinity).padding(10).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 14)) }
    private func compare(_ title: String, _ left: String?, _ right: String?) -> some View { VStack(spacing: 7) { Text(title).font(.caption.bold()).foregroundStyle(AppTheme.green); HStack { Text((left ?? "—").englishDigits).frame(maxWidth: .infinity, alignment: .leading); Divider().frame(height: 20); Text((right ?? "—").englishDigits).frame(maxWidth: .infinity, alignment: .trailing) }; Divider() }.padding(12) }
    @MainActor private func search(text: String, left: Bool) async { let q = text.trimmingCharacters(in: .whitespacesAndNewlines); guard q.count >= 2 else { return }; if left { loadingLeft = true } else { loadingRight = true }; let results = (try? await APISportsStore.shared.searchPlayers(q)) ?? []; if left { leftResults = results; loadingLeft = false } else { rightResults = results; loadingRight = false } }
}
