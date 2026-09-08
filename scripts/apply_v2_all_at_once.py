from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def read(path): return (ROOT / path).read_text(encoding='utf-8')
def write(path, text): (ROOT / path).write_text(text, encoding='utf-8')

# Reuse the already-reviewed deep-football UX layer first.
subprocess.run(['python3', str(ROOT / 'scripts/apply_deep_football_ux.py')], check=True)

# English digits for all Arabic copy generated through the central formatter.
p = 'Sources/Core/SportsCopy.swift'
s = read(p)
s = s.replace('        return formatter.string(from: date)\n', '        return formatter.string(from: date).englishDigits\n')
s = s.replace('        return "منذ \\(count) \\((3...10).contains(count) ? plural : one)"\n', '        return "منذ \\(count) \\((3...10).contains(count) ? plural : one)".englishDigits\n')
write(p, s)

# Wire the new power center into More.
p = 'Sources/Views/V2Personalization.swift'
s = read(p)
needle = '                    NavigationLink { V2DiscoverView() } label: { card("البحث", "ابحث عن نادي أو لاعب", "magnifyingglass") }\n'
insert = needle + '                    NavigationLink { V2PowerCenterView() } label: { card("90+ 2.0", "الأدوات والتحليلات والإعدادات المتقدمة", "bolt.fill") }\n'
if 'NavigationLink { V2PowerCenterView() }' not in s:
    if needle not in s: raise RuntimeError('More power center marker missing')
    s = s.replace(needle, insert, 1)
# Favorite counts always render with English digits.
s = s.replace('Text("\\(count)").font(.caption)', 'Text(String(count)).font(.caption).monospacedDigit()')
write(p, s)

# Matches: English digits in day picker/counts and honor Spoiler Mode.
p = 'Sources/Views/V2MatchExperience.swift'
s = read(p)
s = s.replace('Text(day.formatted(.dateTime.day())).font(.headline.bold())', 'Text(day.formatted(.dateTime.day()).englishDigits).font(.headline.bold()).monospacedDigit()')
s = s.replace('Text("\\(group.items.count) مباراة").font(.caption)', 'Text("\\(group.items.count) مباراة".englishDigits).font(.caption).monospacedDigit()')
if '@AppStorage(V2PreferenceKey.spoilerMode)' not in s:
    s = s.replace('struct V2MatchesView: View {\n', 'struct V2MatchesView: View {\n    @AppStorage(V2PreferenceKey.spoilerMode) private var spoilerMode = false\n', 1)
write(p, s)

# Home counts/results use monospaced English digits where quick UX was injected.
p = 'Sources/Views/V2HomeView.swift'
s = read(p)
s = s.replace('Text(value).font(.headline.bold()).monospacedDigit()', 'Text(value.englishDigits).font(.headline.bold()).monospacedDigit()')
write(p, s)

# Root owns product-level deep links and keeps RTL text while numbers are formatted explicitly.
p = 'Sources/Views/RootView.swift'
s = read(p)
if '.onOpenURL' not in s:
    s = s.replace('        .task { network.start() }\n', '        .task { network.start() }\n        .onOpenURL { url in\n            guard url.scheme == V2DeepLink.scheme else { return }\n            switch url.host {\n            case "match": selection = 1\n            case "team", "player": selection = 2\n            case "league": selection = 4\n            default: break\n            }\n        }\n', 1)
write(p, s)

print('Applied 90+ 2.0 integrated UX, English digits and power features')
