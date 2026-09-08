import SwiftUI

struct V2PlayerComparisonLabView: View {
    @AppStorage("favoritePlayerIDs") private var favoritePlayerIDs = ""
    @State private var leftID = ""
    @State private var rightID = ""
    @State private var leftPlayer: APIPlusPlayer?
    @State private var rightPlayer: APIPlusPlayer?
    @State private var leftStats: [APIPlusPlayerSeasonStat] = []
    @State private var rightStats: [APIPlusPlayerSeasonStat] = []
    @State private var loading = false
    @State private var error: String?

    private var ids: [String] { SavedFavoriteIDs.parse(favoritePlayerIDs) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                TopBar(title: "مقارنة اللاعبين", subtitle: "من بيانات الموسم المنشورة")
                if ids.count < 2 {
                    ContentUnavailableView("تابع لاعبين على الأقل", systemImage: "person.2", description: Text("اختر لاعبين من البحث ثم ارجع للمقارنة."))
                } else {
                    selectors
                    if loading { ProgressView("جارٍ تحميل المقارنة…").tint(AppTheme.green).padding() }
                    if let error { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal, 16) }
                    if let leftPlayer, let rightPlayer { comparison(leftPlayer, rightPlayer) }
                }
            }.padding(.bottom, 30)
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .navigationTitle("مقارنة اللاعبين")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: favoritePlayerIDs) { prepareSelection() }
        .task(id: "\(leftID)|\(rightID)") { await load() }
    }

    private var selectors: some View {
        HStack(spacing: 10) {
            Picker("اللاعب الأول", selection: $leftID) {
                ForEach(ids, id: \.self) { Text($0.englishDigits).tag($0) }
            }
            .pickerStyle(.menu)
            Picker("اللاعب الثاني", selection: $rightID) {
                ForEach(ids, id: \.self) { Text($0.englishDigits).tag($0) }
            }
            .pickerStyle(.menu)
        }
        .tint(AppTheme.green)
        .padding(.horizontal, 16)
    }

    @ViewBuilder private func comparison(_ left: APIPlusPlayer, _ right: APIPlusPlayer) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                playerHeader(left)
                Text("VS").font(.caption.bold()).foregroundStyle(AppTheme.muted)
                playerHeader(right)
            }
            .padding(16)
            .background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 16)

            metric("المشاركات", aggregate(leftStats, \.appearances), aggregate(rightStats, \.appearances))
            metric("الدقائق", aggregate(leftStats, \.minutes), aggregate(rightStats, \.minutes))
            metric("الأهداف", aggregate(leftStats, \.goals), aggregate(rightStats, \.goals))
            metric("التمريرات الحاسمة", aggregate(leftStats, \.assists), aggregate(rightStats, \.assists))
            metric("البطاقات الصفراء", aggregate(leftStats, \.yellowCards), aggregate(rightStats, \.yellowCards))
            metric("البطاقات الحمراء", aggregate(leftStats, \.redCards), aggregate(rightStats, \.redCards))
            ratingMetric
            Text("المقارنة تجمع فقط القيم المنشورة للموسم المتاح ولا تفترض بيانات ناقصة.")
                .font(.caption2).foregroundStyle(AppTheme.muted).padding(.horizontal, 16)
        }
        .accessibilityIdentifier("comparison.players")
    }

    private func playerHeader(_ player: APIPlusPlayer) -> some View {
        VStack(spacing: 8) {
            RemoteBadge(url: player.photo).frame(width: 58, height: 58)
            Text(player.name).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(2).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity)
    }

    private func metric(_ title: String, _ left: Int?, _ right: Int?) -> some View {
        HStack(spacing: 8) {
            Text(left.map(String.init) ?? "—").font(.headline).monospacedDigit().frame(width: 64)
            Text(title).font(.caption).foregroundStyle(AppTheme.muted).frame(maxWidth: .infinity)
            Text(right.map(String.init) ?? "—").font(.headline).monospacedDigit().frame(width: 64)
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private var ratingMetric: some View {
        let left = averageRating(leftStats)
        let right = averageRating(rightStats)
        return HStack(spacing: 8) {
            Text(left ?? "—").font(.headline).monospacedDigit().frame(width: 64)
            Text("متوسط التقييم").font(.caption).foregroundStyle(AppTheme.muted).frame(maxWidth: .infinity)
            Text(right ?? "—").font(.headline).monospacedDigit().frame(width: 64)
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private func aggregate(_ stats: [APIPlusPlayerSeasonStat], _ keyPath: KeyPath<APIPlusPlayerSeasonStat, Int?>) -> Int? {
        let values = stats.compactMap { $0[keyPath: keyPath] }
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    private func averageRating(_ stats: [APIPlusPlayerSeasonStat]) -> String? {
        let values = stats.compactMap { $0.rating.flatMap(Double.init) }
        guard !values.isEmpty else { return nil }
        return String(format: "%.2f", values.reduce(0, +) / Double(values.count)).englishDigits
    }

    @MainActor private func prepareSelection() {
        let current = ids
        if !current.contains(leftID) { leftID = current.first ?? "" }
        if !current.contains(rightID) || rightID == leftID { rightID = current.dropFirst().first ?? "" }
    }

    @MainActor private func load() async {
        guard !leftID.isEmpty, !rightID.isEmpty, leftID != rightID else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            async let lp = APISportsStore.shared.player(id: leftID)
            async let rp = APISportsStore.shared.player(id: rightID)
            async let ls = APISportsStore.shared.playerSeasonStats(playerID: leftID)
            async let rs = APISportsStore.shared.playerSeasonStats(playerID: rightID)
            let result = try await (lp, rp, ls, rs)
            try Task.checkCancellation()
            leftPlayer = result.0; rightPlayer = result.1; leftStats = result.2; rightStats = result.3
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}

struct V2LeagueFormDashboardView: View {
    @State private var leagueID = "307"
    @State private var rows: [APIPlusStanding] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                TopBar(title: "فورمة الأندية", subtitle: "التسلسل المنشور من المصدر")
                Picker("البطولة", selection: $leagueID) {
                    ForEach(LeagueOption.featured) { league in
                        Text(league.arabicName).tag(league.apiFootballID)
                    }
                }
                .pickerStyle(.menu).tint(AppTheme.green).padding(.horizontal, 16)

                if loading { ProgressView("جارٍ التحميل…").tint(AppTheme.green).padding() }
                if let error { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal, 16) }
                ForEach(rows) { row in
                    HStack(spacing: 10) {
                        RemoteBadge(url: row.logo).frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(SportsArabic.team(row.team)).font(.subheadline.bold()).foregroundStyle(.white)
                            Text("#\(row.rank) • \(row.points) نقطة".englishDigits).font(.caption2).foregroundStyle(AppTheme.muted)
                        }
                        Spacer()
                        formChips(row.form)
                    }
                    .padding(13)
                    .background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 16)
                }
                if !loading && error == nil && rows.isEmpty {
                    ContentUnavailableView("الفورمة غير منشورة حاليًا", systemImage: "chart.line.uptrend.xyaxis")
                }
                Text("W فوز • D تعادل • L خسارة — كما نشرها مزود البيانات للموسم الحالي.")
                    .font(.caption2).foregroundStyle(AppTheme.muted).padding(.horizontal, 16)
            }.padding(.bottom, 30)
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .navigationTitle("فورمة الأندية")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: leagueID) { await load() }
        .accessibilityIdentifier("league.formDashboard")
    }

    private func formChips(_ value: String?) -> some View {
        let letters = Array((value ?? "").suffix(5))
        return HStack(spacing: 4) {
            ForEach(Array(letters.enumerated()), id: \.offset) { _, letter in
                Text(String(letter))
                    .font(.caption2.bold())
                    .foregroundStyle(letter == "W" ? .black : .white)
                    .frame(width: 24, height: 24)
                    .background(letter == "W" ? AppTheme.green : (letter == "D" ? Color.white.opacity(0.18) : Color.red.opacity(0.55)), in: Circle())
            }
        }
    }

    @MainActor private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            rows = try await APISportsStore.shared.standings(leagueID: leagueID)
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}
