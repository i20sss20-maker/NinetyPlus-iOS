from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def read(path): return (ROOT / path).read_text(encoding='utf-8')
def write(path, text): (ROOT / path).write_text(text, encoding='utf-8')

p = 'Sources/Views/PublicLeagueTableView.swift'
s = read(p)

if 'league.standingInsights' not in s:
    needle = '''                                    HStack(spacing: 6) {
                                        metric("فوز", value: entry.display("wins"))
                                        metric("تعادل", value: entry.display("ties"))
                                        metric("خسارة", value: entry.display("losses"))
                                        metric("له", value: entry.display("pointsFor"))
                                        metric("عليه", value: entry.display("pointsAgainst"))
                                    }
'''
    replacement = needle + '''                                    VStack(alignment: .leading, spacing: 7) {
                                        if let leaderGap = pointsGapToLeader(entry, in: group.standings.entries) {
                                            Label(leaderGap == 0 ? "متصدر الجدول" : "فارق المتصدر: \\(leaderGap) نقطة".englishDigits, systemImage: "flag.checkered")
                                                .font(.caption).foregroundStyle(leaderGap == 0 ? AppTheme.green : AppTheme.muted)
                                        }
                                        if let adjacent = adjacentPointsGap(entry, in: group.standings.entries) {
                                            Label("فارق أقرب مركز: \\(adjacent) نقطة".englishDigits, systemImage: "arrow.up.arrow.down")
                                                .font(.caption).foregroundStyle(AppTheme.muted)
                                        }
                                        ShareLink(item: standingShareText(entry, in: group.standings.entries)) {
                                            Label("مشاركة ترتيب النادي", systemImage: "square.and.arrow.up")
                                                .font(.caption.bold()).foregroundStyle(AppTheme.green)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityIdentifier("league.standingInsights")
'''
    if needle in s:
        s = s.replace(needle, replacement, 1)

    helper_needle = '''    private func rankValue(_ entry: PublicLeagueTable.Entry) -> Int {
        Int(entry.display("rank")) ?? Int.max
    }
'''
    helpers = helper_needle + '''
    private func pointsValue(_ entry: PublicLeagueTable.Entry) -> Int? {
        guard let stat = entry.stats.first(where: { $0.name == "points" }), let value = stat.value, value.isFinite else { return nil }
        return Int(value.rounded())
    }

    private func pointsGapToLeader(_ entry: PublicLeagueTable.Entry, in entries: [PublicLeagueTable.Entry]) -> Int? {
        guard let current = pointsValue(entry), let leader = entries.compactMap(pointsValue).max() else { return nil }
        return max(0, leader - current)
    }

    private func adjacentPointsGap(_ entry: PublicLeagueTable.Entry, in entries: [PublicLeagueTable.Entry]) -> Int? {
        let ordered = entries.sorted { rankValue($0) < rankValue($1) }
        guard let index = ordered.firstIndex(where: { $0.id == entry.id }), let current = pointsValue(entry) else { return nil }
        var candidates: [Int] = []
        if index > 0, let value = pointsValue(ordered[index - 1]) { candidates.append(abs(value - current)) }
        if index + 1 < ordered.count, let value = pointsValue(ordered[index + 1]) { candidates.append(abs(value - current)) }
        return candidates.min()
    }

    private func standingShareText(_ entry: PublicLeagueTable.Entry, in entries: [PublicLeagueTable.Entry]) -> String {
        var parts = ["90+", SportsArabic.team(entry.team.displayName), "المركز \\(entry.display(\"rank\"))", "\\(entry.display(\"points\")) نقطة"]
        if let gap = pointsGapToLeader(entry, in: entries), gap > 0 { parts.append("فارق المتصدر \\(gap) نقطة") }
        return parts.joined(separator: " • ").englishDigits
    }
'''
    if helper_needle in s:
        s = s.replace(helper_needle, helpers, 1)

write(p, s)
print('Applied fifth 200-feature batch: standing insights, points gaps and standing sharing')
