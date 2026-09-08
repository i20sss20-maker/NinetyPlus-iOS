import SwiftUI

struct V2DataHealthView: View {
    @StateObject private var network = NetworkStatus.shared
    @ObservedObject private var sports = APISportsStore.shared
    @State private var refreshing = false
    @State private var refreshedAt: Date?

    private var liveCount: Int {
        sports.today.filter { MatchLivePolicy.isLive($0.status) }.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                TopBar(title: "صحة البيانات", subtitle: "تشخيص سريع للمصادر والتحديث")

                VStack(spacing: 0) {
                    statusRow("الشبكة", value: network.isOnline ? "متصل" : "غير متصل", icon: network.isOnline ? "wifi" : "wifi.slash", healthy: network.isOnline)
                    Divider().overlay(AppTheme.border)
                    statusRow("مزود الكرة", value: APIFootballClient.isConfigured ? "مهيأ" : "غير مهيأ", icon: "server.rack", healthy: APIFootballClient.isConfigured)
                    Divider().overlay(AppTheme.border)
                    statusRow("مباريات اليوم", value: String(sports.today.count), icon: "calendar", healthy: true)
                    Divider().overlay(AppTheme.border)
                    statusRow("مباشر الآن", value: String(liveCount), icon: "dot.radiowaves.left.and.right", healthy: true)
                    Divider().overlay(AppTheme.border)
                    statusRow("الموسم", value: SeasonCopy.label(APIFootballClient.currentSeason), icon: "trophy", healthy: true)
                    Divider().overlay(AppTheme.border)
                    statusRow("آخر تحديث", value: lastUpdateText, icon: "clock.arrow.circlepath", healthy: sports.lastUpdated != nil)
                }
                .background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(AppTheme.border))
                .padding(.horizontal, 16)

                if let error = sports.error, !error.isEmpty {
                    Label(error.englishDigits, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 16)
                }

                Button {
                    Task { await refresh() }
                } label: {
                    HStack {
                        if refreshing { ProgressView().tint(.black) }
                        Label(refreshing ? "جارٍ التحديث…" : "تحديث البيانات الآن", systemImage: "arrow.clockwise")
                            .font(.headline)
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.green, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .disabled(refreshing || !network.isOnline || !APIFootballClient.isConfigured)
                .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 8) {
                    Label("سياسة التشخيص", systemImage: "checkmark.shield.fill")
                        .font(.subheadline.bold()).foregroundStyle(AppTheme.green)
                    Text("تعطل قسم واحد لا يعني تعطل مركز المباراة كاملًا. 90+ يحتفظ بالبيانات الصالحة ويعزل فشل الأحداث أو الإحصائيات أو التشكيلة لكل قسم على حدة.")
                        .font(.caption).foregroundStyle(AppTheme.muted)
                    Text("لا يعرض هذا المركز مفاتيح API أو أي معلومات شخصية.")
                        .font(.caption2).foregroundStyle(AppTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(15)
                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppTheme.border))
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 30)
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .navigationTitle("صحة البيانات")
        .navigationBarTitleDisplayMode(.inline)
        .task { network.start() }
        .accessibilityIdentifier("data.healthCenter")
    }

    private var lastUpdateText: String {
        guard let date = sports.lastUpdated ?? refreshedAt else { return "لم يتم بعد" }
        return SportsDisplayDate.label(date, pattern: "HH:mm")
    }

    private func statusRow(_ title: String, value: String, icon: String, healthy: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(healthy ? AppTheme.green : .orange)
                .frame(width: 30)
            Text(title).font(.subheadline).foregroundStyle(.white)
            Spacer()
            Text(value.englishDigits).font(.caption.bold()).foregroundStyle(healthy ? AppTheme.green : .orange)
        }
        .padding(14)
    }

    @MainActor private func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        await sports.refreshToday(force: true)
        refreshedAt = Date()
        if sports.error == nil { V2Haptics.success() }
    }
}
