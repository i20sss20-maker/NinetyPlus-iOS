import SwiftUI
import UserNotifications

struct V2ReminderCenterView: View {
    struct Reminder: Identifiable {
        let id: String
        let title: String
        let body: String
        let date: Date?
    }

    @State private var reminders: [Reminder] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                TopBar(title: "مركز التذكيرات", subtitle: "تنبيهات المباريات المجدولة على هذا الجهاز")

                if loading {
                    ProgressView("جارٍ قراءة التذكيرات…").tint(AppTheme.green).padding(30)
                }

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 16)
                }

                if !reminders.isEmpty {
                    HStack {
                        Text("\(reminders.count) تذكير".englishDigits).font(.caption.bold()).foregroundStyle(AppTheme.muted)
                        Spacer()
                        Button("إلغاء الكل", role: .destructive) { cancelAll() }
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 18)
                }

                ForEach(reminders) { reminder in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(alignment: .top) {
                            Image(systemName: "bell.badge.fill").foregroundStyle(AppTheme.green)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(reminder.title.englishDigits).font(.subheadline.bold()).foregroundStyle(.white)
                                if !reminder.body.isEmpty {
                                    Text(reminder.body.englishDigits).font(.caption).foregroundStyle(AppTheme.muted)
                                }
                            }
                            Spacer()
                            Button(role: .destructive) { cancel(reminder.id) } label: {
                                Image(systemName: "trash")
                            }
                        }
                        if let date = reminder.date {
                            Label(SportsDisplayDate.label(date, pattern: "EEEE d MMMM • HH:mm"), systemImage: "clock")
                                .font(.caption2).foregroundStyle(AppTheme.muted)
                        }
                    }
                    .padding(14)
                    .background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppTheme.border))
                    .padding(.horizontal, 16)
                }

                if !loading && error == nil && reminders.isEmpty {
                    ContentUnavailableView("ما عندك تذكيرات مباريات", systemImage: "bell.slash", description: Text("من مركز المباراة اختر التذكير قبل البداية وبيظهر هنا."))
                        .padding(.top, 30)
                }

                Text("التذكيرات تُحفظ محليًا في iOS. إلغاء التذكير هنا لا يلغي متابعة المباراة أو تثبيتها.")
                    .font(.caption2).foregroundStyle(AppTheme.muted)
                    .padding(.horizontal, 18)
            }
            .padding(.bottom, 30)
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .navigationTitle("التذكيرات")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .accessibilityIdentifier("reminders.center")
    }

    @MainActor private func load() async {
        loading = true; error = nil
        defer { loading = false }
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        reminders = requests.compactMap { request in
            guard request.identifier.hasPrefix("ninetyplus.reminder.") else { return nil }
            let date: Date?
            if let trigger = request.trigger as? UNCalendarNotificationTrigger {
                date = trigger.nextTriggerDate()
            } else {
                date = nil
            }
            return Reminder(id: request.identifier, title: request.content.title, body: request.content.body, date: date)
        }
        .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    @MainActor private func cancel(_ id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        reminders.removeAll { $0.id == id }
        V2Haptics.impact()
    }

    @MainActor private func cancelAll() {
        let ids = reminders.map(\.id)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        reminders.removeAll()
        V2Haptics.success()
    }
}
