from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
def read(path): return (ROOT / path).read_text(encoding='utf-8')
def write(path, text): (ROOT / path).write_text(text, encoding='utf-8')

subprocess.run(['python3', str(ROOT / 'scripts/apply_deep_football_ux.py')], check=True)

p = 'Sources/Core/SportsCopy.swift'
s = read(p)
s = s.replace('        return formatter.string(from: date)\n', '        return formatter.string(from: date).englishDigits\n')
s = s.replace('        return "منذ \\(count) \\((3...10).contains(count) ? plural : one)"\n', '        return "منذ \\(count) \\((3...10).contains(count) ? plural : one)".englishDigits\n')
write(p, s)

p = 'Sources/Views/V2Personalization.swift'
s = read(p)
if 'NavigationLink { V2PowerCenterView() }' not in s:
    power = '                    NavigationLink { V2PowerCenterView() } label: { card("90+ 2.0", "الأدوات والتحليلات والإعدادات المتقدمة", "bolt.fill") }\n'
    candidates = [
        '                    statusCard\n',
        '                    NavigationLink { EnhancedTransfersView() } label: { card("الانتقالات", "آخر أخبار سوق الانتقالات", "arrow.left.arrow.right") }\n',
        '                    TopBar(title: "المزيد")\n',
    ]
    inserted = False
    for marker in candidates:
        if marker in s:
            if marker == '                    statusCard\n':
                s = s.replace(marker, power + marker, 1)
            else:
                s = s.replace(marker, marker + power, 1)
            inserted = True
            break
    if not inserted:
        raise RuntimeError('More power center insertion point missing after all supported transformations')
s = s.replace('Text("\\(count)").font(.caption)', 'Text(String(count)).font(.caption).monospacedDigit()')
write(p, s)

p = 'Sources/Views/V2MatchExperience.swift'
s = read(p)
s = s.replace('Text(day.formatted(.dateTime.day())).font(.headline.bold())', 'Text(day.formatted(.dateTime.day()).englishDigits).font(.headline.bold()).monospacedDigit()')
s = s.replace('Text("\\(group.items.count) مباراة").font(.caption)', 'Text("\\(group.items.count) مباراة".englishDigits).font(.caption).monospacedDigit()')
s = s.replace('Text(MatchLivePolicy.statusText(m.status, elapsed: m.elapsed)).font(.caption2.bold())', 'Text(MatchLivePolicy.statusText(m.status, elapsed: m.elapsed).englishDigits).font(.caption2.bold()).monospacedDigit()')
s = s.replace('return value.text.isEmpty ? "—" : value.text', 'return value.text.isEmpty ? "—" : value.text.englishDigits')

if '@AppStorage(V2PreferenceKey.spoilerMode) private var spoilerMode = false' not in s:
    marker = '    @AppStorage("notificationsEnabled") private var notificationsEnabled = false\n'
    if marker not in s: raise RuntimeError('spoiler storage marker missing')
    s = s.replace(marker, marker + '    @AppStorage(V2PreferenceKey.spoilerMode) private var spoilerMode = false\n', 1)
if 'if spoilerMode && !FixturePhase.isUpcoming(m.status)' not in s:
    marker = '        VStack(spacing: 5) {\n            if !FixturePhase.isUpcoming(m.status), let h = m.homeScore, let a = m.awayScore {'
    replacement = '        VStack(spacing: 5) {\n            if spoilerMode && !FixturePhase.isUpcoming(m.status) {\n                Image(systemName: "eye.slash.fill").font(.title3).foregroundStyle(AppTheme.muted)\n                Text("النتيجة مخفية").font(.caption2).foregroundStyle(AppTheme.muted)\n            } else if !FixturePhase.isUpcoming(m.status), let h = m.homeScore, let a = m.awayScore {'
    if marker not in s: raise RuntimeError('score spoiler marker missing')
    s = s.replace(marker, replacement, 1)

if 'case "متقدم": return [.events, .stats]' not in s:
    s = s.replace('        case "تحليل 90+": return [.events, .stats]\n', '        case "تحليل 90+": return [.events, .stats]\n        case "متقدم": return [.events, .stats]\n', 1)
if '"متقدم"], selected: $tab)' not in s:
    s = s.replace('SegmentBar(items: ["نظرة عامة", "تحليل 90+", "الأحداث", "الإحصائيات", "التشكيلة", "المواجهات"], selected: $tab)', 'SegmentBar(items: ["نظرة عامة", "تحليل 90+", "متقدم", "الأحداث", "الإحصائيات", "التشكيلة", "المواجهات"], selected: $tab)', 1)
if 'V2AdvancedAnalysisView(match: displayMatch' not in s:
    s = s.replace('        case "تحليل 90+":\n            feedback(.events); feedback(.stats); insightView\n', '        case "تحليل 90+":\n            feedback(.events); feedback(.stats); insightView\n        case "متقدم":\n            feedback(.events); feedback(.stats); V2AdvancedAnalysisView(match: displayMatch, stats: store.stats, events: store.events)\n', 1)

if 'LiveMatchActivityCoordinator.updateIfRunning' not in s:
    s = s.replace('                current = updated\n                lastObserved = updated\n', '                current = updated\n                lastObserved = updated\n                if #available(iOS 16.1, *) { await LiveMatchActivityCoordinator.updateIfRunning(match: updated) }\n', 1)
if 'LiveMatchActivityCoordinator.end(matchID: match.id)' not in s:
    s = s.replace('            followedMatchIDs = ids.sorted().joined(separator: ",")\n            return\n', '            followedMatchIDs = ids.sorted().joined(separator: ",")\n            if #available(iOS 16.1, *) { await LiveMatchActivityCoordinator.end(matchID: match.id) }\n            return\n', 1)
if 'LiveMatchActivityCoordinator.startOrUpdate(match: displayMatch)' not in s:
    marker = '        followedMatchIDs = ids.sorted().joined(separator: ",")\n    }\n'
    if marker not in s: raise RuntimeError('match follow completion marker missing')
    s = s.replace(marker, '        followedMatchIDs = ids.sorted().joined(separator: ",")\n        if #available(iOS 16.1, *) { await LiveMatchActivityCoordinator.startOrUpdate(match: displayMatch) }\n    }\n', 1)
if 'ShareLink(item: V2Share.match(displayMatch))' not in s:
    marker = '                Spacer()\n                if let date = store.lastLiveUpdate {'
    controls = '                Spacer()\n                ShareLink(item: V2Share.match(displayMatch)) { Image(systemName: "square.and.arrow.up").foregroundStyle(AppTheme.green).padding(8).background(AppTheme.cardRaised, in: Circle()) }\n                Button { Task { permissionNotice = await V2Calendar.addMatch(home: displayMatch.home, away: displayMatch.away, kickoff: displayMatch.date) ? "تمت إضافة المباراة للتقويم." : "تعذر إضافة المباراة للتقويم." } } label: { Image(systemName: "calendar.badge.plus").foregroundStyle(AppTheme.green).padding(8).background(AppTheme.cardRaised, in: Circle()) }\n                if let date = store.lastLiveUpdate {'
    if marker not in s: raise RuntimeError('match action marker missing')
    s = s.replace(marker, controls, 1)

if 'func preference(_ key: String, default defaultValue: Bool = true)' not in s:
    marker = '        let title: String\n        switch notice {'
    replacement = '''        func preference(_ key: String, default defaultValue: Bool = true) -> Bool {
            let defaults = UserDefaults.standard
            return defaults.object(forKey: key) == nil ? defaultValue : defaults.bool(forKey: key)
        }
        switch notice {
        case .started where !preference(V2PreferenceKey.notifyKickoff): return
        case .scoreChanged where !preference(V2PreferenceKey.notifyGoals): return
        default: break
        }
        let title: String
        switch notice {'''
    if marker not in s: raise RuntimeError('notification preference marker missing')
    s = s.replace(marker, replacement, 1)
write(p, s)

p = 'Sources/Views/V2HomeView.swift'
s = read(p)
s = s.replace('Text(value).font(.headline.bold()).monospacedDigit()', 'Text(value.englishDigits).font(.headline.bold()).monospacedDigit()')
write(p, s)

p = 'Sources/Views/RootView.swift'
s = read(p)
if '@AppStorage(V2PreferenceKey.lowDataMode)' not in s:
    marker = '    @State private var selection = 0\n'
    if marker not in s: raise RuntimeError('root low-data storage marker missing')
    s = s.replace(marker, marker + '    @AppStorage(V2PreferenceKey.lowDataMode) private var lowDataMode = false\n', 1)
if 'let effectiveDelay = lowDataMode' not in s:
    marker = '                let delay = AppRefreshPolicy.matchInterval(hasLiveMatches: hasLiveMatches)\n                do { try await Task.sleep(for: .seconds(delay)) } catch { return }\n'
    replacement = '                let delay = AppRefreshPolicy.matchInterval(hasLiveMatches: hasLiveMatches)\n                let effectiveDelay = lowDataMode ? max(delay, hasLiveMatches ? 240 : 900) : delay\n                do { try await Task.sleep(for: .seconds(effectiveDelay)) } catch { return }\n'
    if marker not in s: raise RuntimeError('root low-data interval marker missing')
    s = s.replace(marker, replacement, 1)
if '.onOpenURL' not in s:
    marker = '        .task { network.start() }\n'
    if marker not in s: raise RuntimeError('root deep-link marker missing')
    s = s.replace(marker, marker + '        .onOpenURL { url in\n            guard url.scheme == V2DeepLink.scheme else { return }\n            switch url.host {\n            case "match": selection = 1\n            case "team", "player": selection = 2\n            case "league": selection = 4\n            default: break\n            }\n        }\n', 1)
write(p, s)

print('Applied 90+ 2.0 integrated UX, English digits, spoiler/low-data runtime, preference-aware notifications, power features, advanced analysis and Live Activities')
