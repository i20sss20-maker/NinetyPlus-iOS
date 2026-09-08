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
    marker = '                    statusCard\n'
    power = '                    NavigationLink { V2PowerCenterView() } label: { card("90+ 2.0", "الأدوات والتحليلات والإعدادات المتقدمة", "bolt.fill") }\n'
    if marker not in s: raise RuntimeError('More power center insertion point missing')
    s = s.replace(marker, power + marker, 1)
s = s.replace('Text("\\(count)").font(.caption)', 'Text(String(count)).font(.caption).monospacedDigit()')
write(p, s)

p = 'Sources/Views/V2MatchExperience.swift'
s = read(p)
s = s.replace('Text(day.formatted(.dateTime.day())).font(.headline.bold())', 'Text(day.formatted(.dateTime.day()).englishDigits).font(.headline.bold()).monospacedDigit()')
s = s.replace('Text("\\(group.items.count) مباراة").font(.caption)', 'Text("\\(group.items.count) مباراة".englishDigits).font(.caption).monospacedDigit()')
s = s.replace('Text(MatchLivePolicy.statusText(m.status, elapsed: m.elapsed)).font(.caption2.bold())', 'Text(MatchLivePolicy.statusText(m.status, elapsed: m.elapsed).englishDigits).font(.caption2.bold()).monospacedDigit()')
s = s.replace('return value.text.isEmpty ? "—" : value.text', 'return value.text.isEmpty ? "—" : value.text.englishDigits')
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
write(p, s)

p = 'Sources/Views/V2HomeView.swift'
s = read(p)
s = s.replace('Text(value).font(.headline.bold()).monospacedDigit()', 'Text(value.englishDigits).font(.headline.bold()).monospacedDigit()')
write(p, s)

p = 'Sources/Views/RootView.swift'
s = read(p)
if '.onOpenURL' not in s:
    marker = '        .task { network.start() }\n'
    if marker not in s: raise RuntimeError('root deep-link marker missing')
    s = s.replace(marker, marker + '        .onOpenURL { url in\n            guard url.scheme == V2DeepLink.scheme else { return }\n            switch url.host {\n            case "match": selection = 1\n            case "team", "player": selection = 2\n            case "league": selection = 4\n            default: break\n            }\n        }\n', 1)
write(p, s)

print('Applied 90+ 2.0 integrated UX, English digits, power features and Live Activities')
