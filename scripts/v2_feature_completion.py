"""Last-stage, guarded integration of the documented V2 features.

Do not claim this implements an unavailable, numbered 200-item conversation list.
All edits are staged before writing; changed upstream anchors fail the build.
"""
from pathlib import Path


def once(text, old, new, label):
    if new in text:
        if text.count(new) != 1 or old in text.replace(new, "", 1):
            raise RuntimeError(f'V2 feature integration: duplicate {label}')
        return text
    if text.count(old) != 1:
        raise RuntimeError(f'V2 feature integration: ambiguous or missing {label}')
    return text.replace(old, new, 1)


def patch(contents):
    result = dict(contents)
    name = 'Sources/Views/V2PowerCenter.swift'
    source = result[name]
    source = once(source, 'NavigationLink { V2LineupBuilderView() }',
                  'NavigationLink { V2SavedLineupsView() }', 'lineup destination')
    source = once(source, 'NavigationLink { PlayerCompareView() }',
                  'NavigationLink { V2PlayerStatsComparisonView() }', 'comparison destination')
    anchor = '\nstruct V2LineupBuilderView: View {'
    if anchor in source:
        tail = source[source.index(anchor):]
        if tail.count('\nstruct ') != 2 or '\nstruct PlayerCompareView: View {' not in tail:
            raise RuntimeError('V2 feature integration: old tool definitions changed')
        source = source[:source.index(anchor)] + '\n'
    for label, screen in [('power.lineup', 'V2SavedLineupsView'), ('power.comparison', 'V2PlayerStatsComparisonView')]:
        if label not in source:
            lines = source.splitlines(keepends=True)
            indexes = [i for i, line in enumerate(lines) if f'NavigationLink {{ {screen}() }}' in line]
            if len(indexes) != 1: raise RuntimeError('tool accessibility anchor missing')
            i = indexes[0]
            lines[i] = lines[i].rstrip() + f'.accessibilityIdentifier("{label}")\n'
            source = ''.join(lines)
    source = once(source, 'يقلل الصور والتحديثات غير الضرورية مع إبقاء النتائج والمباراة الأساسية.',
                  'يقلل وتيرة التحديث التلقائي للنتائج ومركز المباراة. التحديث اليدوي يظل متاحًا.', 'low data copy')
    result[name] = source

    name = 'Sources/Views/RootView.swift'
    source = result[name]
    source = once(source, '    @State private var selection = 0\n',
                  '    @State private var selection = 0\n    @State private var linkedRoute: V2ContentRoute?\n', 'root route state')
    old = '''        .onOpenURL { url in
            guard url.scheme == V2DeepLink.scheme else { return }
            switch url.host {
            case "match": selection = 1
            case "team", "player": selection = 2
            case "league": selection = 4
            default: break
            }
        }'''
    new = '''        .onOpenURL { url in
            guard let route = V2ContentRoute(url: url) else { return }
            linkedRoute = route
        }
        .sheet(item: $linkedRoute) { route in
            V2LinkedDestinationView(route: route).id(route.id)
                .environment(\\.locale, SportsDisplayDate.locale)
                .environment(\\.calendar, SportsDisplayDate.calendar)
                .environment(\\.timeZone, SportsDisplayDate.calendar.timeZone)
                .environment(\\.layoutDirection, .rightToLeft)
        }'''
    result[name] = once(source, old, new, 'deep link handler')

    name = 'Sources/Core/V2ProductPlatform.swift'
    source = result[name]
    source = once(source, 'static func match(_ match: APIPlusMatch) -> String {',
                  'static func match(_ match: APIPlusMatch, hidingScore: Bool = false) -> String {', 'share signature')
    source = once(source, 'if let h = match.homeScore, let a = match.awayScore, !FixturePhase.isUpcoming(match.status)',
                  'if !hidingScore, let h = match.homeScore, let a = match.awayScore, !FixturePhase.isUpcoming(match.status)', 'share spoiler policy')
    source = once(source, 'V2DeepLink.match(match.id)?.absoluteString',
                  'V2DeepLink.match(match.id, kickoff: match.date)?.absoluteString', 'share date')
    old = '''enum V2DeepLink {
    static let scheme = "ninetyplus"
    static func match(_ id: String) -> URL? { URL(string: "\\(scheme)://match/\\(id)") }
    static func team(_ id: String) -> URL? { URL(string: "\\(scheme)://team/\\(id)") }
    static func player(_ id: String) -> URL? { URL(string: "\\(scheme)://player/\\(id)") }
    static func league(_ id: String) -> URL? { URL(string: "\\(scheme)://league/\\(id)") }
}'''
    new = '''enum V2DeepLink {
    static let scheme = "ninetyplus"
    static func match(_ id: String, kickoff: Date? = nil) -> URL? { V2ContentRoute(kind: .match, identifier: id, kickoff: kickoff)?.url }
    static func team(_ id: String) -> URL? { V2ContentRoute(kind: .team, identifier: id)?.url }
    static func player(_ id: String) -> URL? { V2ContentRoute(kind: .player, identifier: id)?.url }
    static func league(_ id: String) -> URL? { V2ContentRoute(kind: .league, identifier: id)?.url }
}'''
    result[name] = once(source, old, new, 'validated link encoding')

    name = 'Sources/Views/V2MatchExperience.swift'
    source = result[name]
    source = once(source, 'ShareLink(item: V2Share.match(displayMatch))',
                  'ShareLink(item: V2Share.match(displayMatch, hidingScore: spoilerMode))', 'score-safe sharing')
    source = once(source, '    @AppStorage(V2PreferenceKey.spoilerMode) private var spoilerMode = false\n',
                  '    @AppStorage(V2PreferenceKey.spoilerMode) private var spoilerMode = false\n    @AppStorage(V2PreferenceKey.lowDataMode) private var lowDataMode = false\n', 'match low data setting')
    source = once(source,
        '                guard let seconds = MatchLivePolicy.interval(status: current.status, kickoff: current.date) else { break }',
        '                guard let baseInterval = MatchLivePolicy.interval(status: current.status, kickoff: current.date) else { break }\n                let seconds = lowDataMode ? max(baseInterval, 120) : baseInterval', 'match low data interval')
    result[name] = source
    return result


def apply_features(root):
    root = Path(root)
    paths = ['Sources/Views/V2PowerCenter.swift', 'Sources/Views/RootView.swift',
             'Sources/Core/V2ProductPlatform.swift', 'Sources/Views/V2MatchExperience.swift']
    originals = {p: (root / p).read_text(encoding='utf-8') for p in paths}
    for path, text in patch(originals).items():
        if text != originals[path]: (root / path).write_text(text, encoding='utf-8')
    print('V2 features integrated: saved lineups, season comparison, content routes, spoiler-safe sharing and match low-data mode')


if __name__ == '__main__':
    apply_features(Path(__file__).resolve().parents[1])
