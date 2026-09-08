import SwiftUI

struct PremiumPlayerRadar: View {
    let player: APIPlusPlayer
    @State private var resource = PageResource<[APIPlusPlayerSeasonStat]>()
    @State private var selectedID = ""
    @State private var retry = 0

    private var selected: APIPlusPlayerSeasonStat? {
        resource.value?.first { $0.id == selectedID } ?? resource.value?.first
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                TopBar(title: "Player Radar", subtitle: "مؤشرات الموسم من بيانات المصدر")
                HStack(spacing: 14) {
                    RemoteBadge(url: player.photo).frame(width: 72, height: 72).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 5) {
                        Text(player.name).font(.title3.bold())
                        if let nationality = player.nationality { Text(SportsArabic.country(nationality) ?? nationality).font(.caption).foregroundStyle(AppTheme.muted) }
                    }
                    Spacer()
                }.padding(16).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 20))

                PageLoadFeedback(loading: resource.isLoading || resource.key == nil,
                                 hasValue: resource.value != nil,
                                 message: resource.errorMessage,
                                 updatedAt: resource.lastUpdated) { retry += 1 }

                if let values = resource.value, !values.isEmpty {
                    Picker("الموسم والبطولة", selection: $selectedID) {
                        ForEach(values) { item in
                            Text("\(SeasonCopy.label(item.season)) • \(SportsArabic.team(item.team)) • \(SportsArabic.league(item.league))").tag(item.id)
                        }
                    }.pickerStyle(.menu).accessibilityIdentifier("player.radar.season")
                }

                if let stat = selected {
                    summary(stat)
                    per90(stat)
                    Text("هذه المؤشرات ليست Percentiles أمام جميع لاعبي المركز؛ التطبيق لا يملك حاليًا مجموعة مقارنة موحدة وموثوقة لكل مركز وبطولة. لذلك نعرض الأرقام الفعلية والمعدلات فقط.")
                        .font(.caption).foregroundStyle(AppTheme.muted)
                } else if resource.value?.isEmpty == true, resource.errorMessage == nil {
                    ContentUnavailableView("لا توجد إحصائيات منشورة", systemImage: "chart.bar")
                }
            }.padding(16).padding(.bottom, 30)
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .navigationTitle("Player Radar").navigationBarTitleDisplayMode(.inline)
        .task(id: retry) { await load() }
        .refreshable { retry += 1 }
        .onDisappear { resource.invalidate() }
        .accessibilityIdentifier("player.radar.screen")
    }

    private func summary(_ stat: APIPlusPlayerSeasonStat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(SeasonCopy.label(stat.season)) • \(SportsArabic.team(stat.team))").font(.headline)
            Text(SportsArabic.league(stat.league)).font(.caption).foregroundStyle(AppTheme.muted)
            HStack { metric("مباريات", stat.appearances); metric("دقائق", stat.minutes); metric("أهداف", stat.goals) }
            HStack { metric("صناعة", stat.assists); metric("صفراء", stat.yellowCards); metric("حمراء", stat.redCards) }
            HStack {
                Text("تقييم المصدر").foregroundStyle(AppTheme.muted)
                Spacer()
                Text(stat.rating?.englishDigits ?? "—").monospacedDigit()
            }.font(.subheadline)
            if let position = stat.position, !position.isEmpty { Text("المركز: \(position)").font(.caption).foregroundStyle(AppTheme.muted) }
        }.padding(16).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 20))
    }

    private func per90(_ stat: APIPlusPlayerSeasonStat) -> some View {
        let goals = V2ComparisonMath.per90(count: stat.goals, minutes: stat.minutes)
        let assists = V2ComparisonMath.per90(count: stat.assists, minutes: stat.minutes)
        return VStack(alignment: .leading, spacing: 12) {
            Text("معدل كل 90 دقيقة").font(.headline)
            radarRow("الأهداف", value: goals, benchmark: 1.0)
            radarRow("الصناعة", value: assists, benchmark: 1.0)
            Text("طول الشريط مقياس بصري من 0 إلى 1.00 لكل 90 دقيقة، وليس ترتيبًا بين اللاعبين. القيم الأعلى من 1.00 تُعرض رقميًا كاملة ويصل الشريط لنهايته فقط.")
                .font(.caption2).foregroundStyle(AppTheme.muted)
        }.padding(16).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private func radarRow(_ title: String, value: Double?, benchmark: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(title); Spacer(); Text(V2ComparisonMath.display(value)).monospacedDigit() }
            GeometryReader { geometry in
                let fraction = min(max((value ?? 0) / benchmark, 0), 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.soft)
                    Capsule().fill(AppTheme.green).frame(width: geometry.size.width * fraction)
                }
            }.frame(height: 9)
        }.font(.subheadline)
    }

    private func metric(_ title: String, _ value: Int?) -> some View {
        VStack(spacing: 5) {
            Text(V2ComparisonMath.display(value)).font(.title3.bold()).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(AppTheme.muted)
        }.frame(maxWidth: .infinity)
    }

    @MainActor private func load() async {
        let token = resource.begin(key: player.id)
        defer { resource.cancel(token: token) }
        do {
            let values = try await APISportsStore.shared.playerSeasonStats(playerID: player.id)
            try Task.checkCancellation()
            guard resource.succeed(values, token: token) else { return }
            if !values.contains(where: { $0.id == selectedID }) { selectedID = values.first?.id ?? "" }
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            resource.fail(error.localizedDescription, token: token)
        }
    }
}
