from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def read(path): return (ROOT / path).read_text(encoding='utf-8')
def write(path, text): (ROOT / path).write_text(text, encoding='utf-8')

# OLED black is a real runtime preference, not a separate theme fork.
p = 'Sources/Core/Core.swift'
s = read(p)
s = s.replace('    static let bg = Color(red: 0.006, green: 0.024, blue: 0.031)\n    static let card = Color(red: 0.018, green: 0.060, blue: 0.071)\n    static let cardRaised = Color(red: 0.027, green: 0.087, blue: 0.100)\n', '''    static var bg: Color { UserDefaults.standard.bool(forKey: V2FeaturePreferences.oledBlack) ? .black : Color(red: 0.006, green: 0.024, blue: 0.031) }
    static var card: Color { UserDefaults.standard.bool(forKey: V2FeaturePreferences.oledBlack) ? Color(red: 0.010, green: 0.010, blue: 0.010) : Color(red: 0.018, green: 0.060, blue: 0.071) }
    static var cardRaised: Color { UserDefaults.standard.bool(forKey: V2FeaturePreferences.oledBlack) ? Color(red: 0.025, green: 0.025, blue: 0.025) : Color(red: 0.027, green: 0.087, blue: 0.100) }
''')
write(p, s)

# Product entry point. Use a broad stable anchor because earlier transforms may add cards.
p = 'Sources/Views/V2Personalization.swift'
s = read(p)
if 'V2200FeatureCenterView()' not in s:
    anchor = '                    statusCard\n'
    entry = '                    NavigationLink { V2200FeatureCenterView() } label: { card("ميزات 90+ المتقدمة", "التثبيت، OLED، التنبيهات، كثافة العرض والمزيد", "sparkles") }\n'
    if anchor not in s:
        raise RuntimeError('200-feature center anchor missing')
    s = s.replace(anchor, entry + anchor, 1)
write(p, s)

# Match list filters: live/upcoming/finished + followed + pinned.
p = 'Sources/Views/V2MatchExperience.swift'
s = read(p)
if '@AppStorage("v2.pinnedMatchIDs")' not in s:
    s = s.replace('    @State private var retryID = 0\n', '    @State private var retryID = 0\n    @AppStorage("favoriteTeamIDs") private var favoriteTeamIDs = ""\n    @AppStorage("v2.pinnedMatchIDs") private var pinnedMatchIDs = ""\n', 1)
    s = s.replace('        case "المنتهية": return matches.filter { FixturePhase.isFinished($0.status) }\n        default: return matches\n', '''        case "المنتهية": return matches.filter { FixturePhase.isFinished($0.status) }
        case "متابعاتي":
            let ids = Set(SavedFavoriteIDs.parse(favoriteTeamIDs))
            return matches.filter { ($0.homeID.map(ids.contains) ?? false) || ($0.awayID.map(ids.contains) ?? false) }
        case "مثبتة":
            let ids = Set(pinnedMatchIDs.split(separator: ",").map(String.init))
            return matches.filter { ids.contains($0.id) }
        default: return matches
''', 1)
    s = s.replace('SegmentBar(items: ["الكل", "مباشر", "القادمة", "المنتهية"], selected: $filter)', 'SegmentBar(items: ["الكل", "مباشر", "القادمة", "المنتهية", "متابعاتي", "مثبتة"], selected: $filter)', 1)

# Match-center pinning and reminder scheduling. Use short stable anchors after all older transforms.
if '@State private var pinRevision = 0' not in s:
    state_anchor = '    @State private var permissionNotice: String?\n'
    if state_anchor not in s: raise RuntimeError('match center state anchor missing')
    s = s.replace(state_anchor, state_anchor + '    @State private var pinRevision = 0\n    @State private var reminderBusy = false\n    @AppStorage(V2FeaturePreferences.reminderLeadMinutes) private var reminderLeadMinutes = 30\n', 1)
    follow_anchor = '    private var isFollowed: Bool { SavedFavoriteIDs.parse(followedMatchIDs).contains(match.id) }\n'
    if follow_anchor not in s: raise RuntimeError('match center followed anchor missing')
    s = s.replace(follow_anchor, follow_anchor + '    private var isPinned: Bool { _ = pinRevision; return PinnedMatchStore.contains(match.id) }\n', 1)

if 'MatchReminderScheduler.schedule(match: displayMatch' not in s:
    button_anchor = '                }.buttonStyle(.plain).disabled(followBusy)\n'
    controls = '''                Button {
                    _ = PinnedMatchStore.toggle(match.id)
                    pinRevision += 1
                } label: {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .foregroundStyle(isPinned ? .black : AppTheme.green)
                        .frame(width: 42, height: 42)
                        .background(isPinned ? AppTheme.green : AppTheme.cardRaised, in: Circle())
                        .overlay(Circle().stroke(isPinned ? Color.clear : AppTheme.border))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPinned ? "إلغاء تثبيت المباراة" : "تثبيت المباراة")

                Button {
                    Task {
                        reminderBusy = true
                        defer { reminderBusy = false }
                        do {
                            try await MatchReminderScheduler.schedule(match: displayMatch, leadMinutes: reminderLeadMinutes)
                            permissionNotice = "تم ضبط تذكير قبل المباراة بـ \\(reminderLeadMinutes) دقيقة".englishDigits
                            V2Haptics.success()
                        } catch {
                            permissionNotice = "تعذر ضبط التذكير حاليًا"
                        }
                    }
                } label: {
                    Image(systemName: "clock.badge")
                        .foregroundStyle(AppTheme.green)
                        .frame(width: 42, height: 42)
                        .background(AppTheme.cardRaised, in: Circle())
                        .overlay(Circle().stroke(AppTheme.border))
                }
                .buttonStyle(.plain)
                .disabled(reminderBusy || !FixturePhase.isUpcoming(displayMatch.status))
                .accessibilityLabel("تذكير قبل المباراة")
'''
    if button_anchor not in s: raise RuntimeError('match center follow button anchor missing')
    s = s.replace(button_anchor, button_anchor + controls, 1)
write(p, s)

# Compact/comfortable match density on the home feed.
p = 'Sources/Views/V2HomeView.swift'
s = read(p)
if '@AppStorage(V2FeaturePreferences.compactMatches)' not in s:
    s = s.replace('private struct DashboardMatchRow: View {\n    let match: APIPlusMatch\n', 'private struct DashboardMatchRow: View {\n    let match: APIPlusMatch\n    @AppStorage(V2FeaturePreferences.compactMatches) private var compactMatches = false\n', 1)
    s = s.replace('        }.foregroundStyle(.white).padding(14).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 18))\n', '        }.foregroundStyle(.white).padding(.vertical, compactMatches ? 9 : 14).padding(.horizontal, 14).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 18))\n', 1)
write(p, s)

print('Applied 90+ 200-feature batch: OLED, power center, pinned/followed filters, pinning, reminders and density')
