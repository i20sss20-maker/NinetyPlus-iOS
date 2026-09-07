"""Deterministic build-time source fixes used by every distributable and visual QA build.
Keeps Arabic presentation Gregorian and preserves explicit metric units regardless of device locale.
"""
from pathlib import Path

match = Path("Sources/Views/V2MatchExperience.swift")
s = match.read_text()
replacements = {
    '@State private var selectedDate = Calendar.current.startOfDay(for: Date())': '@State private var selectedDate = SportsDisplayDate.calendar.startOfDay(for: Date())',
    '@State private var dayAnchor = Calendar.current.startOfDay(for: Date())': '@State private var dayAnchor = SportsDisplayDate.calendar.startOfDay(for: Date())',
    'private var selectedDay: Date { Calendar.current.startOfDay(for: selectedDate) }': 'private var selectedDay: Date { SportsDisplayDate.calendar.startOfDay(for: selectedDate) }',
    'private var days: [Date] { (-3...3).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: dayAnchor) } }': 'private var days: [Date] { (-3...3).compactMap { SportsDisplayDate.calendar.date(byAdding: .day, value: $0, to: dayAnchor) } }',
    'guard let updatedAt, Calendar.current.isDateInToday(selectedDate),': 'guard let updatedAt, SportsDisplayDate.calendar.isDateInToday(selectedDate),',
    'let selected = Calendar.current.isDate(day, inSameDayAs: selectedDate)': 'let selected = SportsDisplayDate.calendar.isDate(day, inSameDayAs: selectedDate)',
    'Text(day.formatted(.dateTime.day())).font(.headline.bold())': 'Text(SportsDisplayDate.label(day, pattern: "d")).font(.headline.bold())',
    'Text(day.formatted(.dateTime.month(.abbreviated))).font(.caption2)': 'Text(SportsDisplayDate.label(day, pattern: "MMM")).font(.caption2)',
    'if Calendar.current.isDateInToday(day) { return "اليوم" }': 'if SportsDisplayDate.calendar.isDateInToday(day) { return "اليوم" }',
    'if Calendar.current.isDateInYesterday(day) { return "أمس" }': 'if SportsDisplayDate.calendar.isDateInYesterday(day) { return "أمس" }',
    'if Calendar.current.isDateInTomorrow(day) { return "غدًا" }': 'if SportsDisplayDate.calendar.isDateInTomorrow(day) { return "غدًا" }',
    'let formatter = DateFormatter()\n        formatter.locale = Locale(identifier: "ar_SA")\n        formatter.dateFormat = "EEE"\n        return formatter.string(from: day)': 'return SportsDisplayDate.label(day, pattern: "EEE")',
    'Text(date.formatted(date: .abbreviated, time: .shortened))': 'Text(SportsDisplayDate.label(date, pattern: "d MMMM yyyy، HH:mm"))',
    'Text(date, style: .time)': 'Text(SportsDisplayDate.label(date, pattern: "HH:mm"))',
    'infoRow("الموعد", date.formatted(date: .abbreviated, time: .shortened))': 'infoRow("الموعد", SportsDisplayDate.label(date, pattern: "d MMMM yyyy، HH:mm"))',
}
for old, new in replacements.items():
    s = s.replace(old, new)
match.write_text(s)

player = Path("Sources/Views/V2Discovery.swift")
s = player.read_text()
s = s.replace('info("الطول", player.height?.replacingOccurrences(of: "cm", with: "سم"))', 'info("الطول", measurement(player.height, unit: "سم"))')
s = s.replace('info("الوزن", player.weight?.replacingOccurrences(of: "kg", with: "كجم"))', 'info("الوزن", measurement(player.weight, unit: "كجم"))')
needle = '    private func metric(_ title: String, _ value: Int?) -> some View {'
helper = '''    private func measurement(_ raw: String?, unit: String) -> String? {\n        guard let raw else { return nil }\n        let digits = raw.filter { $0.isNumber || $0 == "." }\n        guard !digits.isEmpty else { return nil }\n        return "\\(digits) \\(unit)"\n    }\n'''
if helper not in s:
    s = s.replace(needle, helper + needle)
player.write_text(s)

print("Applied release UI fixes")
