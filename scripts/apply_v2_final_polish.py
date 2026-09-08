from pathlib import Path

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

# Match Center resilience: the app's match IDs can be canonical `np:` IDs. Use the
# canonical Railway detail endpoint first so fixture/events/stats/lineups remain
# available through cache and provider fallbacks. Direct API-Football calls remain
# only as a compatibility fallback for legacy numeric fixture IDs.
p = 'Sources/Views/V2MatchExperience.swift'
s = read(p)
if 'loadCanonicalDetail' not in s:
    old_load = '''    func load(_ match: APIPlusMatch, force: Bool = false) async {
        guard !Task.isCancelled else { return }
        prepare(match)
        let lackedTeamIDs = current?.homeID == nil || current?.awayID == nil
        await fetchSections(MatchDataSection.allCases, match: match, force: force)
        if lackedTeamIDs, !Task.isCancelled, progress.matchID == match.id,
           progress.state(.h2h).value == nil, current?.homeID != nil, current?.awayID != nil {
            await loadSection(.h2h, match: match)
        }
    }

    func refreshLive(_ match: APIPlusMatch, sections: [MatchDataSection]) async {
        guard !Task.isCancelled else { return }
        await fetchSections(Array(Set([.fixture] + sections)), match: match, force: false)
    }
'''
    new_load = '''    func load(_ match: APIPlusMatch, force: Bool = false) async {
        guard !Task.isCancelled else { return }
        prepare(match)
        let lackedTeamIDs = current?.homeID == nil || current?.awayID == nil
        let primary: [MatchDataSection] = [.fixture, .events, .stats, .lineups]
        let canonicalLoaded = await loadCanonicalDetail(match, sections: primary, force: force)
        if !canonicalLoaded, Int(match.id) != nil {
            await fetchSections(primary, match: match, force: force)
        }
        if !Task.isCancelled, progress.matchID == match.id,
           progress.state(.h2h).value == nil, current?.homeID != nil, current?.awayID != nil,
           (lackedTeamIDs || force || progress.state(.h2h).lastUpdated == nil) {
            await loadSection(.h2h, match: match, force: force)
        }
    }

    func refreshLive(_ match: APIPlusMatch, sections: [MatchDataSection]) async {
        guard !Task.isCancelled else { return }
        let primary = Array(Set([MatchDataSection.fixture] + sections.filter { $0 != .h2h }))
        let canonicalLoaded = await loadCanonicalDetail(match, sections: primary, force: false)
        if !canonicalLoaded, Int(match.id) != nil {
            await fetchSections(primary, match: match, force: false)
        }
    }

    private func loadCanonicalDetail(_ match: APIPlusMatch, sections: [MatchDataSection], force: Bool) async -> Bool {
        guard !Task.isCancelled else { return false }
        prepare(match)
        let requested = Array(Set(sections.filter { $0 != .h2h }))
        var tokens: [MatchDataSection: UUID] = [:]
        for section in requested {
            if let token = progress.begin(section, force: force) { tokens[section] = token }
        }
        guard !tokens.isEmpty else { return true }
        defer {
            for (section, token) in tokens { progress.cancel(section, token: token) }
        }
        do {
            let detail = try await CanonicalSportsClient.detail(matchID: match.id)
            try Task.checkCancellation()
            guard progress.matchID == match.id else { return false }
            current = detail.match.appMatch
            if let token = tokens[.fixture] {
                _ = progress.succeed(.fixture, token: token, hasContent: true)
            }
            if let token = tokens[.events] {
                events = detail.appEvents
                _ = progress.succeed(.events, token: token, hasContent: !events.isEmpty)
            }
            if let token = tokens[.stats] {
                stats = detail.appStatistics
                _ = progress.succeed(.stats, token: token, hasContent: !stats.isEmpty)
            }
            if let token = tokens[.lineups] {
                lineups = detail.appLineups
                _ = progress.succeed(.lineups, token: token, hasContent: !lineups.isEmpty)
            }
            lastObserved = current
            return true
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), progress.matchID == match.id else { return false }
            // The route already has a valid match snapshot from the list/canonical feed.
            // A failed background fixture refresh must never turn the whole page into an error.
            if let token = tokens[.fixture] {
                _ = progress.succeed(.fixture, token: token, hasContent: true)
            }
            let message = error.localizedDescription
            for section in [MatchDataSection.events, .stats, .lineups] {
                if let token = tokens[section] { progress.fail(section, token: token, message: message) }
            }
            return false
        }
    }
'''
    if old_load not in s: raise RuntimeError('match center load marker missing')
    s = s.replace(old_load, new_load, 1)

    marker = '''        if section == .h2h {
            guard displayed.homeID != nil, displayed.awayID != nil else {
                progress.markUnavailable(.h2h)
                return
            }
            progress.markAvailable(.h2h)
        }
        guard let token = progress.begin(section, force: force) else { return }
'''
    replacement = '''        if section == .h2h {
            guard displayed.homeID != nil, displayed.awayID != nil else {
                progress.markUnavailable(.h2h)
                return
            }
            progress.markAvailable(.h2h)
        } else if Int(match.id) == nil {
            _ = await loadCanonicalDetail(match, sections: [section], force: force)
            return
        }
        guard let token = progress.begin(section, force: force) else { return }
'''
    if marker not in s: raise RuntimeError('match center section marker missing')
    s = s.replace(marker, replacement, 1)
write(p, s)

print('Applied 90+ 2.0 final polish: Latin numerals, recent searches, in-app transfer reading and canonical Match Center resilience')
