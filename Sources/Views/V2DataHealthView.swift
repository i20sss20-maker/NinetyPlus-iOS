import SwiftUI
import Foundation

struct V2DataHealthView: View {
    @StateObject private var network = NetworkStatus.shared
    @ObservedObject private var sports = APISportsStore.shared
    @State private var refreshing = false
    @State private var refreshedAt: Date?
    @State private var backendHealth: NinetyPlusBackendHealth?
    @State private var backendProbeFailed = false
    @State private var publicSourceHealthy: Bool?
    @State private var publicTeamCount: Int?

    private var liveCount: Int {
        sports.today.filter { MatchLivePolicy.isLive($0.status) }.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                TopBar(title: "صحة البيانات", subtitle: "تشخيص حي للمصادر والتحديث")

                VStack(spacing: 0) {
                    statusRow("الشبكة", value: network.isOnline ? "متصل" : "غير متصل", icon: network.isOnline ? "wifi" : "wifi.slash", healthy: network.isOnline)
                    Divider().overlay(AppTheme.border)
                    sourceRow("Railway Backend", state: backendStateText, icon: "server.rack", healthy: backendHealth?.ok == true && !backendProbeFailed)
                    Divider().overlay(AppTheme.border)
                    sourceRow("مزود الكرة", state: providerStateText, icon: "sportscourt", healthy: backendHealth?.allowsDirectProviderRequests ?? APIFootballClient.isConfigured)
                    Divider().overlay(AppTheme.border)
                    sourceRow("مصدر الترتيب العام", state: publicStateText, icon: "tablecells", healthy: publicSourceHealthy == true)
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

                if let remaining = backendHealth?.providerBudgetRemaining {
                    HStack {
                        Label("حالة سعة المزود", systemImage: "gauge.with.dots.needle.67percent")
                            .font(.caption.bold()).foregroundStyle(.white)
                        Spacer()
                        Text("متبقي \(remaining) طلب".englishDigits)
                            .font(.caption.bold()).foregroundStyle(remaining > 0 ? AppTheme.green : .orange)
                    }
                    .padding(14)
                    .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 16)
                }

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
                        Label(refreshing ? "جارٍ الفحص والتحديث…" : "فحص المصادر وتحديث البيانات", systemImage: "arrow.clockwise")
                            .font(.headline)
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.green, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .disabled(refreshing || !network.isOnline)
                .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 8) {
                    Label("سياسة التشخيص", systemImage: "checkmark.shield.fill")
                        .font(.subheadline.bold()).foregroundStyle(AppTheme.green)
                    Text("تعطل قسم أو مصدر واحد لا يعني تعطل التطبيق كاملًا. 90+ يحتفظ بالبيانات الصالحة ويعزل فشل الأحداث أو الإحصائيات أو التشكيلة لكل قسم على حدة.")
                        .font(.caption).foregroundStyle(AppTheme.muted)
                    Text("الفحص يختبر توفر المصادر فقط، ولا يعرض مفاتيح API أو أي معلومات شخصية.")
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
        .task {
            network.start()
            guard network.isOnline else { return }
            await probeSources()
        }
        .accessibilityIdentifier("data.healthCenter")
    }

    private var backendStateText: String {
        if backendProbeFailed { return "متعذر الآن" }
        if let health = backendHealth { return health.ok ? "متاح" : "غير جاهز" }
        return "غير مفحوص"
    }

    private var providerStateText: String {
        guard let health = backendHealth else { return APIFootballClient.isConfigured ? "مهيأ" : "غير مهيأ" }
        if health.providerRemoteBlocked == true { return "محدود مؤقتًا" }
        if let remaining = health.providerBudgetRemaining, remaining <= 0 { return "وصل الحد المؤقت" }
        return health.allowsDirectProviderRequests ? "جاهز" : "غير متاح"
    }

    private var publicStateText: String {
        guard let publicSourceHealthy else { return "غير مفحوص" }
        if publicSourceHealthy, let publicTeamCount { return "متاح • \(publicTeamCount) فريق".englishDigits }
        return "متعذر الآن"
    }

    private var lastUpdateText: String {
        guard let date = sports.lastUpdated ?? refreshedAt else { return "لم يتم بعد" }
        return SportsDisplayDate.label(date, pattern: "HH:mm")
    }

    private func statusRow(_ title: String, value: String, icon: String, healthy: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(healthy ? AppTheme.green : .orange).frame(width: 30)
            Text(title).font(.subheadline).foregroundStyle(.white)
            Spacer()
            Text(value.englishDigits).font(.caption.bold()).foregroundStyle(healthy ? AppTheme.green : .orange)
        }
        .padding(14)
    }

    private func sourceRow(_ title: String, state: String, icon: String, healthy: Bool) -> some View {
        statusRow(title, value: state, icon: icon, healthy: healthy)
    }

    @MainActor private func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        await probeSources()
        await sports.refreshToday(force: true)
        refreshedAt = Date()
        if sports.error == nil && backendHealth?.ok == true { V2Haptics.success() }
    }

    @MainActor private func probeSources() async {
        backendProbeFailed = false
        publicSourceHealthy = nil
        publicTeamCount = nil

        do {
            backendHealth = try await APIFootballClient.health()
        } catch {
            backendHealth = nil
            backendProbeFailed = true
        }

        do {
            guard let url = URL(string: "https://site.web.api.espn.com/apis/v2/sports/soccer/ksa.1/standings") else {
                publicSourceHealthy = false
                return
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count < 2_000_000 else {
                publicSourceHealthy = false
                return
            }
            let table = try PublicLeagueTable.decodeCurrent(data)
            publicTeamCount = table.children.reduce(0) { $0 + $1.standings.entries.count }
            publicSourceHealthy = true
        } catch {
            publicSourceHealthy = false
        }
    }
}
