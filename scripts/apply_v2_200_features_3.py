from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def read(path): return (ROOT / path).read_text(encoding='utf-8')
def write(path, text): (ROOT / path).write_text(text, encoding='utf-8')

p = 'Sources/Views/V2MatchExperience.swift'
s = read(p)

# Add factual pre/post and H2H summaries into the overview without changing data sources.
if 'V2MatchShareTools.phaseSummary' not in s:
    needle = '        return VStack(spacing: 12) {\n'
    insert = '''        return VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Label("ملخص 90+", systemImage: "sparkles")
                        .font(.subheadline.bold()).foregroundStyle(AppTheme.green)
                    Spacer()
                    ShareLink(item: V2MatchShareTools.summary(m)) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(AppTheme.green)
                            .frame(width: 36, height: 36)
                            .background(AppTheme.card, in: Circle())
                    }
                    .accessibilityLabel("مشاركة المباراة")
                }
                Text(V2MatchShareTools.phaseSummary(m))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                if let h2h = V2MatchShareTools.h2hSummary(current: m, matches: store.h2h) {
                    Text(h2h).font(.caption).foregroundStyle(AppTheme.muted)
                }
            }
            .padding(14)
            .background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppTheme.border))
            .accessibilityIdentifier("match.prePostSummary")
'''
    if needle in s:
        s = s.replace(needle, insert, 1)

write(p, s)
print('Applied third 200-feature batch: pre/post summary, H2H summary and share action')
