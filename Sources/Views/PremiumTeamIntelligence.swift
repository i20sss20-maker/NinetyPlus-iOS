import SwiftUI

struct PremiumTeamIntelligence: View {
    let homeID: String?
    let homeName: String
    var awayID: String? = nil
    var awayName = ""
    @StateObject private var left = PremiumTeamLoader()
    @StateObject private var right = PremiumTeamLoader()
    @AppStorage(V2PreferenceKey.spoilerMode) private var spoiler = false
    @State private var venue: TeamFormReport.Venue = .all
    @State private var retry = 0
    private func knownID(_ id: String?) -> String? {
        guard let id, let numeric = UInt64(id), numeric > 0 else { return nil }
        return String(numeric)
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                TopBar(title: awayID == nil ? "Team DNA" : "Match Intelligence", subtitle: "قراءة العينة المتاحة • لا توقعات فوز")
                Text("المصدر الحالي يعيد نافذة مباريات حديثة محدودة، لا تاريخ الموسم كله. تُستبعد ركلات الترجيح من مؤشر النتائج لعدم توفر نتيجة الترجيح في هذه العينة.")
                    .font(.caption).foregroundStyle(AppTheme.muted)
                Picker("الملعب", selection: $venue) { ForEach(TeamFormReport.Venue.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                if spoiler {
                    ContentUnavailableView("التحليل مخفي مع النتائج", systemImage: "eye.slash", description: Text("نتائج المباريات ومؤشر الفورمة قد تكشف ما حدث."))
                } else {
                    report(name: homeName, id: knownID(homeID), loader: left)
                    if awayID != nil { report(name: awayName, id: knownID(awayID), loader: right) }
                    if let a = knownID(homeID), let b = knownID(awayID) {
                        let h2h = TeamFormReport.headToHead((left.state.value ?? []) + (right.state.value ?? []), home: a, away: b)
                        Text("Head-to-Head Lab").font(.title3.bold())
                        Text("المواجهات الموجودة داخل العينة فقط. غياب مواجهة هنا لا يعني أن الفريقين لم يتقابلا من قبل.").font(.caption).foregroundStyle(AppTheme.muted)
                        if h2h.isEmpty { Text("لا توجد مواجهات مشتركة ضمن البيانات التي وصلت.").font(.caption) }
                        ForEach(h2h) { value in
                            NavigationLink { V2MatchCenterView(match: value.appMatch) } label: { PremiumMatchCard(match: value, spoiler: spoiler) }.buttonStyle(.plain)
                        }
                    }
                }
                Text("مؤشر 90+ = (3 × الفوز + التعادل) ÷ (3 × عدد المباريات) × 100. يظهر من 3 مباريات صالحة فأكثر، ولا يقيس جودة المنافس أو احتمال الفوز القادم.")
                    .font(.caption).foregroundStyle(AppTheme.muted)
            }.padding(16).padding(.bottom, 24)
        }.background(AppTheme.bg.ignoresSafeArea()).navigationTitle("تحليل الفريق").navigationBarTitleDisplayMode(.inline)
        .task(id: "\(homeID ?? "")|\(awayID ?? "")|\(retry)") {
            async let a: Void = load(left, id: homeID, name: homeName)
            async let b: Void = load(right, id: awayID, name: awayName)
            _ = await (a, b)
        }
        .refreshable { retry += 1 }
        .onDisappear { left.cancel(); right.cancel() }
        .accessibilityIdentifier("premium.team.intelligence")
    }
    private func load(_ loader: PremiumTeamLoader, id: String?, name: String) async {
        guard let id = knownID(id) else { return }
        await loader.load(id: id, name: name)
    }
    private func report(name: String, id: String?, loader: PremiumTeamLoader) -> some View {
        let value = TeamFormReport(teamID: id ?? "", matches: loader.state.value ?? [], venue: venue)
        return VStack(alignment: .leading, spacing: 12) {
            Text(SportsArabic.team(name)).font(.title3.bold())
            if id == nil { Text("معرّف النادي غير متاح للتحليل لدى المصدر. لم نحاول تخمينه من الاسم.").font(.caption).foregroundStyle(AppTheme.muted) }
            else {
                PageLoadFeedback(loading: loader.state.isLoading, hasValue: loader.state.value != nil, message: loader.state.errorMessage, updatedAt: loader.state.lastUpdated) { retry += 1 }
                Text("آخر \(value.count) مباريات صالحة متاحة • الأحدث أولًا").font(.caption).foregroundStyle(AppTheme.muted)
                Text(value.formIndex.map { "مؤشر الفورمة \($0) / 100" } ?? "العينة لا تكفي لحساب مؤشر الفورمة").font(.headline).foregroundStyle(AppTheme.green)
                HStack { ForEach(Array(value.form.enumerated()), id: \.offset) { _, item in Text(item).font(.headline).padding(10).background(AppTheme.soft, in: Circle()) } }
                if value.count > 0 {
                    HStack { metric("فوز", value.wins); metric("تعادل", value.draws); metric("خسارة", value.losses) }
                    HStack { metric("سجّل", value.goalsFor); metric("استقبل", value.goalsAgainst); metric("شباك نظيفة", value.cleanSheets) }
                } else { Text("لا توجد مباريات صالحة لهذا الفلتر، فلا نعرض أصفارًا كأنها إحصائيات فعلية.").font(.caption).foregroundStyle(AppTheme.muted) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 20))
    }
    private func metric(_ title: String, _ number: Int) -> some View {
        VStack(spacing: 5) { Text(String(number)).font(.title3.bold()).monospacedDigit(); Text(title).font(.caption2).foregroundStyle(AppTheme.muted) }.frame(maxWidth: .infinity)
    }
}
