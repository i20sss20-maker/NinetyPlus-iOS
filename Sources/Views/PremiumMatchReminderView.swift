import SwiftUI

struct PremiumMatchReminderView: View {
    let match: APIPlusMatch
    @StateObject private var center = MatchReminderCenter.shared
    @State private var selected = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("تذكير قبل المباراة", systemImage: "bell.badge.fill").font(.headline)
            Text("يذكّرك هذا الجهاز قبل موعد البداية المحفوظ. إذا تغيّر موعد المباراة، ألغِ التذكير واضبطه من جديد. تنبيهات الأهداف المباشرة غير متاحة في هذه النسخة.")
                .font(.caption).foregroundStyle(AppTheme.muted)
            Picker("قبل البداية", selection: $selected) {
                ForEach([5, 15, 30, 60], id: \.self) { Text("\($0) دقيقة").tag($0) }
            }.pickerStyle(.segmented)
            if center.isScheduled(matchID: match.id, minutes: selected) {
                Button(role: .destructive) { Task { await center.cancel(matchID: match.id, minutes: selected) } } label: {
                    Label("إلغاء التذكير", systemImage: "bell.slash")
                }.accessibilityIdentifier("match.reminder.cancel")
            } else {
                Button { Task { await center.schedule(match: match, minutesBefore: selected) } } label: {
                    Label("ضبط التذكير", systemImage: "bell.fill")
                }.accessibilityIdentifier("match.reminder.schedule")
            }
            if let message = center.message { Text(message).font(.caption).foregroundStyle(AppTheme.muted) }
        }
        .padding(16).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 20)).padding(.horizontal, 16)
        .task { await center.reload() }
    }
}
