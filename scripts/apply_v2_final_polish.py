from pathlib import Path
from match_center_recovery import apply_match_center_recovery

ROOT = Path(__file__).resolve().parents[1]

def read(path): return (ROOT / path).read_text(encoding='utf-8')
def write(path, text): (ROOT / path).write_text(text, encoding='utf-8')

# Arabic language + Gregorian calendar + Latin 0-9 numerals at the SwiftUI environment level.
p = 'Sources/Core/PublicLeagueTable.swift'
s = read(p)
s = s.replace('Locale(identifier: "ar_SA@calendar=gregorian")', 'Locale(identifier: "ar-SA-u-ca-gregory-nu-latn")')
write(p, s)

# Recent searches: small local history, no account or analytics dependency.
p = 'Sources/Views/V2Discovery.swift'
s = read(p)
if '@AppStorage("v2.recentSearches")' not in s:
    s = s.replace('    @State private var retry = 0\n', '    @State private var retry = 0\n    @AppStorage("v2.recentSearches") private var recentSearchesRaw = ""\n', 1)
    s = s.replace('    private var entered: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }\n', '    private var entered: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }\n    private var recentSearches: [String] { recentSearchesRaw.split(separator: "|").map(String.init).filter { !$0.isEmpty } }\n', 1)
    marker = '            HStack(spacing: 8) {\n                ForEach(["الاتحاد", "الهلال", "رونالدو"], id: \\.self) { name in\n'
    replacement = '''            HStack(spacing: 8) {
                ForEach(["الاتحاد", "الهلال", "رونالدو"], id: \.self) { name in
'''
    if marker in s: s = s.replace(marker, replacement, 1)
    end = '            }\n        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 22)).padding(.horizontal, 16)\n'
    recent = '''            }
            if !recentSearches.isEmpty {
                Divider().overlay(AppTheme.border)
                HStack { Text("بحثت مؤخرًا").font(.caption.bold()).foregroundStyle(AppTheme.muted); Spacer(); Button("مسح") { recentSearchesRaw = "" }.font(.caption2).foregroundStyle(AppTheme.green) }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recentSearches.prefix(6), id: \.self) { value in
                            Button(value) { query = value }.font(.caption.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 11).padding(.vertical, 8).background(AppTheme.soft, in: Capsule())
                        }
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 22)).padding(.horizontal, 16)
'''
    if end not in s: raise RuntimeError('search introduction marker missing')
    s = s.replace(end, recent, 1)
    s = s.replace('.onSubmit(of: .search) { dismissKeyboard() }', '.onSubmit(of: .search) { rememberSearch(); dismissKeyboard() }', 1)
    marker = '    @MainActor private func dismissKeyboard() {'
    helper = '''    private func rememberSearch() {
        let value = entered
        guard value.count >= 2, !value.contains("|") else { return }
        var values = recentSearches.filter { $0 != value }
        values.insert(value, at: 0)
        recentSearchesRaw = values.prefix(6).joined(separator: "|")
    }
'''
    if marker not in s: raise RuntimeError('search helper marker missing')
    s = s.replace(marker, helper + marker, 1)
    s = s.replace('Text("\\(count) نتيجة")', 'Text("\\(count) نتيجة".englishDigits)')
write(p, s)

# Keep transfer reading inside the app and normalize provider-supplied numerals.
p = 'Sources/Views/EnhancedTransfersView.swift'
s = read(p)
s = s.replace('Link(destination: url) { reportCard(article) }', 'InAppWebLink(url: url) { reportCard(article) }')
s = s.replace('Text(item.title).font(.caption.bold())', 'Text(item.title.englishDigits).font(.caption.bold())')
s = s.replace('Text(article.title).font(.headline)', 'Text(article.title.englishDigits).font(.headline)')
s = s.replace('Text(article.source.isEmpty ? "المصدر" : article.source)', 'Text((article.source.isEmpty ? "المصدر" : article.source).englishDigits)')
write(p, s)

# News provider text can contain Arabic-Indic digits; normalize it at presentation time.
p = 'Sources/Views/EnhancedNewsView.swift'
s = read(p)
s = s.replace('Text(article.title).font(', 'Text(article.title.englishDigits).font(')
s = s.replace('Text(article.source).font(', 'Text(article.source.englishDigits).font(')
write(p, s)

# Match Center partial-failure policy. apply_release_ui_fixes.py already routes `np:`
# matches through CanonicalSportsClient.detail. If that background detail request
# fails, the match snapshot shown in the header is still valid and must not become
# a page-level fixture error. Only detail sections keep their own retry state.
p = 'Sources/Views/V2MatchExperience.swift'
s = read(p)
s = apply_match_center_recovery(s)
write(p, s)

print('Applied 90+ 2.0 final polish: Latin numerals, recent searches, in-app transfer reading and partial Match Center fallback')
