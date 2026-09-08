import SwiftUI

@MainActor final class V2ComparisonSide: ObservableObject {
    @Published private(set) var query = ""
    @Published private(set) var player: APIPlusPlayer?
    @Published private(set) var results = PageResource<[APIPlusPlayer]>()
    @Published private(set) var stats = PageResource<[APIPlusPlayerSeasonStat]>()
    @Published var selectedStatID = ""
    @Published var searchRetry = 0
    @Published var statsRetry = 0
    var selectedStat: APIPlusPlayerSeasonStat? {
        guard stats.key == player?.id else { return nil }
        return stats.value?.first { $0.id == selectedStatID }
    }
    func edit(_ text: String) {
        let normalized = String(text.prefix(100))
        guard normalized != query else { return }
        results = PageResource(); stats = PageResource(); player = nil; selectedStatID = ""
        query = normalized
    }
    func choose(_ value: APIPlusPlayer?) {
        // Choosing the same ID does not restart SwiftUI's ID-keyed stats task.
        // Preserve its value and in-flight token instead of leaving an empty pane.
        if let value, player?.id == value.id { player = value; return }
        results = PageResource(); stats = PageResource(); selectedStatID = ""
        player = value; query = value?.name ?? ""
    }
    func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard player == nil, text.count >= 2, !Task.isCancelled else { return }
        let token = results.begin(key: text)
        defer { results.cancel(token: token) }
        do {
            try await Task.sleep(for: .milliseconds(350))
            let values = try await APISportsStore.shared.searchPlayers(text)
            try Task.checkCancellation()
            guard player == nil, query.trimmingCharacters(in: .whitespacesAndNewlines) == text else { return }
            results.succeed(values, token: token)
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            results.fail(error.localizedDescription, token: token)
        }
    }
    func loadStats() async {
        guard let id = player?.id, !Task.isCancelled else { return }
        let token = stats.begin(key: id)
        defer { stats.cancel(token: token) }
        do {
            let values = try await APISportsStore.shared.playerSeasonStats(playerID: id)
            try Task.checkCancellation()
            guard player?.id == id, stats.succeed(values, token: token) else { return }
            if !values.contains(where: { $0.id == selectedStatID }) { selectedStatID = values.first?.id ?? "" }
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            stats.fail(error.localizedDescription, token: token)
        }
    }
    func cancel() { results.invalidate(); stats.invalidate() }
}

@MainActor struct V2PlayerStatsComparisonView: View {
    @StateObject private var left = V2ComparisonSide()
    @StateObject private var right = V2ComparisonSide()
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                TopBar(title: "مقارنة اللاعبين", subtitle: "بيانات المصدر مع تحديد الموسم والبطولة")
                HStack(alignment: .top, spacing: 10) {
                    V2ComparisonPicker(model: left, title: "اللاعب الأول", identifier: "left")
                    V2ComparisonPicker(model: right, title: "اللاعب الثاني", identifier: "right")
                }
                if let a = left.player, let b = right.player {
                    Button("تبديل اللاعبين") { left.choose(b); right.choose(a) }
                        .accessibilityIdentifier("comparison.swap")
                    VStack(spacing: 0) {
                        row("الجنسية", SportsArabic.country(a.nationality), SportsArabic.country(b.nationality))
                        row("تاريخ الميلاد", a.birth, b.birth)
                        row("الطول", a.height, b.height)
                        row("الوزن", a.weight, b.weight)
                    }.background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
                    if let a = left.selectedStat, let b = right.selectedStat, a.season != b.season {
                        Text("تنبيه: بيانات اللاعبين من موسمين مختلفين، كما يظهر في اختيار كل لاعب.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if left.selectedStat != nil || right.selectedStat != nil { statistics }
                    Text("— تعني أن المصدر لم ينشر القيمة. معدل كل 90 دقيقة محسوب من العدد والدقائق المنشورين فقط.")
                        .font(.caption).foregroundStyle(AppTheme.muted)
                }
            }.padding(16).padding(.bottom, 30)
        }.background(AppTheme.bg.ignoresSafeArea()).navigationTitle("مقارنة").navigationBarTitleDisplayMode(.inline)
    }
    private var statistics: some View {
        VStack(spacing: 0) {
            statRow("المباريات", \.appearances)
            statRow("الدقائق", \.minutes)
            statRow("الأهداف", \.goals)
            statRow("صناعة الأهداف", \.assists)
            statRow("البطاقات الصفراء", \.yellowCards)
            statRow("البطاقات الحمراء", \.redCards)
            row("تقييم المصدر", left.selectedStat?.rating, right.selectedStat?.rating)
            row("أهداف لكل 90 دقيقة",
                V2ComparisonMath.display(V2ComparisonMath.per90(count: left.selectedStat?.goals, minutes: left.selectedStat?.minutes)),
                V2ComparisonMath.display(V2ComparisonMath.per90(count: right.selectedStat?.goals, minutes: right.selectedStat?.minutes)))
            row("صناعة أهداف لكل 90 دقيقة",
                V2ComparisonMath.display(V2ComparisonMath.per90(count: left.selectedStat?.assists, minutes: left.selectedStat?.minutes)),
                V2ComparisonMath.display(V2ComparisonMath.per90(count: right.selectedStat?.assists, minutes: right.selectedStat?.minutes)))
        }.background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 18))
    }
    private func statRow(_ title: String, _ key: KeyPath<APIPlusPlayerSeasonStat, Int?>) -> some View {
        row(title, V2ComparisonMath.display(left.selectedStat?[keyPath: key]), V2ComparisonMath.display(right.selectedStat?[keyPath: key]))
    }
    private func row(_ title: String, _ a: String?, _ b: String?) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.caption.bold()).foregroundStyle(AppTheme.green)
            HStack {
                Text(value(a)).frame(maxWidth: .infinity)
                Divider().frame(height: 20)
                Text(value(b)).frame(maxWidth: .infinity)
            }.font(.subheadline).monospacedDigit()
            Divider()
        }.padding(12)
    }
    private func value(_ text: String?) -> String {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "—" }
        return text.englishDigits
    }
}

@MainActor private struct V2ComparisonPicker: View {
    @ObservedObject var model: V2ComparisonSide
    let title: String
    let identifier: String
    var body: some View {
        VStack(spacing: 10) {
            Text(title).font(.caption.bold()).foregroundStyle(AppTheme.muted)
            TextField("اسم اللاعب", text: Binding(get: { model.query }, set: { model.edit($0) }))
                .textFieldStyle(.roundedBorder).submitLabel(.search)
                .accessibilityIdentifier("comparison.\(identifier).query")
            if let player = model.player {
                RemoteBadge(url: player.photo).frame(width: 66, height: 66).clipShape(Circle())
                Text(player.name).font(.subheadline.bold()).multilineTextAlignment(.center)
                Button("تغيير اللاعب") { model.choose(nil) }
                    .accessibilityIdentifier("comparison.\(identifier).change")
                if model.stats.isLoading { ProgressView() }
                if model.stats.errorMessage != nil {
                    Text("تعذر تحديث الإحصائيات").font(.caption)
                    Button("إعادة المحاولة") { model.statsRetry += 1 }
                }
                if let values = model.stats.value, !values.isEmpty {
                    Picker("الموسم والبطولة", selection: $model.selectedStatID) {
                        ForEach(values) { value in
                            Text("\(SeasonCopy.label(value.season)) • \(SportsArabic.team(value.team)) • \(SportsArabic.league(value.league))").tag(value.id)
                        }
                    }.pickerStyle(.menu)
                    if let selected = model.selectedStat {
                        Text("موسم \(SeasonCopy.label(selected.season))").font(.caption.bold())
                        Text(SportsArabic.team(selected.team)).font(.caption2)
                        Text(SportsArabic.league(selected.league)).font(.caption2)
                        if selected.season != APIFootballClient.currentSeason {
                            Text("آخر موسم متاح، وليس الموسم الحالي").font(.caption2).foregroundStyle(.orange)
                        }
                    }
                } else if model.stats.value?.isEmpty == true, model.stats.errorMessage == nil {
                    Text("لا توجد إحصائيات منشورة").font(.caption)
                }
            } else {
                if model.results.isLoading { ProgressView() }
                if model.results.errorMessage != nil {
                    Text("تعذر البحث الآن").font(.caption)
                    Button("إعادة المحاولة") { model.searchRetry += 1 }
                }
                ForEach((model.results.value ?? []).prefix(8)) { player in
                    Button { model.choose(player) } label: {
                        HStack {
                            RemoteBadge(url: player.photo).frame(width: 28, height: 28)
                            Text(player.name).font(.caption).foregroundStyle(.white)
                        }.padding(6)
                    }.buttonStyle(.plain)
                }
                if model.results.value?.isEmpty == true, !model.results.isLoading, model.results.errorMessage == nil {
                    Text("لا توجد نتائج").font(.caption)
                }
            }
        }.frame(maxWidth: .infinity).padding(8).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16))
        .task(id: "\(model.query)|\(model.searchRetry)") { await model.search() }
        .task(id: "\(model.player?.id ?? "")|\(model.statsRetry)") { await model.loadStats() }
        .onDisappear { model.cancel() }
    }
}
