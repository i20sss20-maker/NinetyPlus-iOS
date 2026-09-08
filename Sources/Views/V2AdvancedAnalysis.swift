import SwiftUI

struct V2AdvancedAnalysisView: View {
    let match: APIPlusMatch
    let stats: [APIStatisticTeam]
    let events: [APIEventItem]

    private struct PairMetric: Identifiable {
        let id: String
        let title: String
        let home: String?
        let away: String?
    }

    var body: some View {
        VStack(spacing: 14) {
            if !pairMetrics.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("مقارنة متقدمة", "أرقام المصدر كما نُشرت")
                    ForEach(pairMetrics) { metric in
                        HStack(spacing: 10) {
                            Text((metric.home ?? "—").englishDigits).font(.headline).monospacedDigit().frame(maxWidth: .infinity, alignment: .leading)
                            Text(metric.title).font(.caption).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                            Text((metric.away ?? "—").englishDigits).font(.headline).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        Divider().overlay(AppTheme.border)
                    }
                }
                .padding(15).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(AppTheme.border))
            }

            if !eventBuckets.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("زخم الأحداث", "مؤشر وصفي من الأحداث المنشورة — ليس توقع فوز")
                    ForEach(eventBuckets, id: \.label) { bucket in
                        HStack(spacing: 9) {
                            Text(bucket.label).font(.caption2.bold()).foregroundStyle(AppTheme.muted).frame(width: 50)
                            GeometryReader { proxy in
                                HStack(spacing: 2) {
                                    Rectangle().fill(AppTheme.green.opacity(0.75)).frame(width: width(bucket.home, total: bucket.home + bucket.away, available: proxy.size.width))
                                    Rectangle().fill(Color.white.opacity(0.20)).frame(width: width(bucket.away, total: bucket.home + bucket.away, available: proxy.size.width))
                                }.clipShape(Capsule())
                            }.frame(height: 10)
                            Text("\(bucket.home)–\(bucket.away)".englishDigits).font(.caption2).monospacedDigit().foregroundStyle(AppTheme.muted).frame(width: 42)
                        }
                    }
                }
                .padding(15).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(AppTheme.border))
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("توفر البيانات", "90+ لا يرسم خرائط من بيانات غير موجودة")
                availabilityRow("xG", available: hasMetric(["expected_goals", "Expected Goals", "xG"]))
                availabilityRow("خريطة التسديد", available: false, note: "تحتاج إحداثيات كل تسديدة")
                availabilityRow("Heat Map", available: false, note: "تحتاج بيانات مواقع اللاعب")
                availabilityRow("خريطة التمرير", available: false, note: "تحتاج إحداثيات التمريرات")
                availabilityRow("الخريطة الدفاعية", available: false, note: "تحتاج إحداثيات التدخلات")
            }
            .padding(15).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(AppTheme.border))
        }.padding(.horizontal, 16)
    }

    private var pairMetrics: [PairMetric] {
        [
            metric("expected_goals", title: "xG", alternatives: ["Expected Goals", "xG"]),
            metric("Ball Possession", title: "الاستحواذ"),
            metric("Total Shots", title: "التسديدات"),
            metric("Shots on Goal", title: "على المرمى"),
            metric("Total passes", title: "التمريرات"),
            metric("Passes %", title: "دقة التمرير")
        ].compactMap { $0 }
    }

    private func metric(_ key: String, title: String, alternatives: [String] = []) -> PairMetric? {
        guard stats.count >= 2 else { return nil }
        let keys = Set([key] + alternatives)
        func value(_ team: APIStatisticTeam) -> String? {
            guard let stat = team.statistics.first(where: { keys.contains($0.type ?? "") }), let value = stat.value else { return nil }
            if case .null = value { return nil }
            let text = value.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text.englishDigits
        }
        let homeTeam = stats.first(where: { normalized($0.team.name) == normalized(match.home) }) ?? stats.first
        let awayTeam = stats.first(where: { normalized($0.team.name) == normalized(match.away) }) ?? stats.dropFirst().first
        guard let homeTeam, let awayTeam else { return nil }
        let home = value(homeTeam), away = value(awayTeam)
        guard home != nil || away != nil else { return nil }
        return PairMetric(id: key, title: title, home: home, away: away)
    }

    private func hasMetric(_ keys: [String]) -> Bool {
        let set = Set(keys)
        return stats.contains { team in team.statistics.contains { set.contains($0.type ?? "") && $0.value?.text.isEmpty == false } }
    }

    private struct MomentumBucket {
        let label: String
        var home: Int
        var away: Int
    }

    private var eventBuckets: [MomentumBucket] {
        guard !events.isEmpty else { return [] }
        var buckets = stride(from: 0, through: 90, by: 15).map { MomentumBucket(label: "\($0)–\($0 + 14)'".englishDigits, home: 0, away: 0) }
        for event in events {
            guard let minute = event.time.elapsed else { continue }
            let index = min(max(minute / 15, 0), buckets.count - 1)
            let weight = eventWeight(event.type)
            let eventTeam = normalized(event.team.name)
            if eventTeam == normalized(match.home) { buckets[index].home += weight }
            else if eventTeam == normalized(match.away) { buckets[index].away += weight }
        }
        return buckets.filter { $0.home + $0.away > 0 }
    }

    private func eventWeight(_ type: String?) -> Int {
        switch type?.lowercased() {
        case "goal": return 3
        case "card", "var": return 2
        case "subst": return 1
        default: return 1
        }
    }

    private func width(_ value: Int, total: Int, available: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        return max(2, available * CGFloat(value) / CGFloat(total))
    }

    private func normalized(_ value: String?) -> String {
        (value ?? "").lowercased().replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: " fc", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sectionTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(title).font(.headline); Text(subtitle).font(.caption2).foregroundStyle(AppTheme.muted) }
    }

    private func availabilityRow(_ title: String, available: Bool, note: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: available ? "checkmark.circle.fill" : "circle.dashed").foregroundStyle(available ? AppTheme.green : AppTheme.muted)
            VStack(alignment: .leading, spacing: 2) { Text(title).font(.subheadline.bold()); if let note, !available { Text(note).font(.caption2).foregroundStyle(AppTheme.muted) } }
            Spacer(); Text(available ? "متاح" : "حسب المصدر").font(.caption2).foregroundStyle(available ? AppTheme.green : AppTheme.muted)
        }
    }
}
