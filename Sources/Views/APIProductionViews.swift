import SwiftUI

// Legacy compatibility layer.
// All production navigation now goes through the V2 screens and the Railway backend.

struct APIKeySetupView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: APIFootballClient.isConfigured ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(APIFootballClient.isConfigured ? AppTheme.green : .orange)
                Text("مصدر بيانات 90+")
                    .font(.title2.bold())
                Text(APIFootballClient.isConfigured
                     ? "الخدمة مربوطة تلقائيًا عبر 90+ Backend. لا يحتاج المستخدم إلى إدخال أي مفتاح API."
                     : "الخدمة الرياضية غير متاحة حاليًا. حاول مرة أخرى لاحقًا.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.bg.ignoresSafeArea())
            .navigationTitle("حالة البيانات")
        }
    }
}

struct APIHomeView: View {
    var body: some View { V2HomeView() }
}

struct APIMatchesView: View {
    var body: some View { V2MatchesView() }
}

struct APICompactMatchCard: View {
    let match: APIPlusMatch

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(match.league)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
                Spacer()
                Text(statusText)
                    .font(.caption.bold())
                    .foregroundStyle(isLive ? AppTheme.green : AppTheme.muted)
            }

            HStack(spacing: 12) {
                team(match.home, match.homeLogo)
                Spacer()
                VStack(spacing: 4) {
                    if let home = match.homeScore, let away = match.awayScore {
                        Text("\(home) - \(away)")
                            .font(.title2.bold())
                    } else if let date = match.date {
                        Text(date, style: .time)
                            .font(.headline)
                            .foregroundStyle(AppTheme.green)
                    }
                    if let elapsed = match.elapsed, isLive {
                        Text("\(elapsed)′")
                            .font(.caption2.bold())
                            .foregroundStyle(AppTheme.green)
                    }
                }
                Spacer()
                team(match.away, match.awayLogo)
            }
        }
        .foregroundStyle(.white)
        .padding(15)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 16)
    }

    private var isLive: Bool { APISportsStore.shared.isLive(match.status) }

    private var statusText: String {
        let value = match.status.uppercased()
        if isLive { return "مباشر" }
        switch value {
        case "FT": return "انتهت"
        case "HT": return "بين الشوطين"
        case "NS": return "لم تبدأ"
        case "PST": return "مؤجلة"
        case "CANC": return "ملغاة"
        case "AET": return "وقت إضافي"
        case "PEN": return "ركلات ترجيح"
        default: return match.status.isEmpty ? "موعد" : match.status
        }
    }

    private func team(_ name: String, _ logo: String?) -> some View {
        VStack(spacing: 5) {
            RemoteBadge(url: logo).frame(width: 42, height: 42)
            Text(name)
                .font(.caption.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 95)
        }
    }
}

struct APIMatchDetailView: View {
    let match: APIPlusMatch
    var body: some View { V2MatchCenterView(match: match) }
}

struct APIDiscoverView: View {
    var body: some View { V2DiscoverView() }
}

struct APITeamView: View {
    let team: APIPlusTeam
    var body: some View { V2TeamView(team: team) }
}

struct APIPlayerView: View {
    let player: APIPlusPlayer
    var body: some View { V2PlayerView(player: player) }
}

struct APIMoreView: View {
    var body: some View { V2MoreView() }
}

struct APIStandingsView: View {
    let league: LeagueOption
    var body: some View { V2LeagueHubView(league: league) }
}
