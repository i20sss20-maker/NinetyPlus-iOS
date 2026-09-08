import SwiftUI

struct APICompactMatchCard: View {
    let match: APIPlusMatch
    @AppStorage(V2PreferenceKey.spoilerMode) private var spoilerMode = false

    var body: some View {
        VStack(spacing: 13) {
            header
            HStack(alignment: .center, spacing: 10) {
                team(match.home, match.homeLogo)
                Spacer(minLength: 6)
                scoreBlock
                Spacer(minLength: 6)
                team(match.away, match.awayLogo)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .background(cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(isLive ? AppTheme.green.opacity(0.26) : AppTheme.border, lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let leagueLogo = match.leagueLogo {
                RemoteBadge(url: leagueLogo).frame(width: 25, height: 25)
            }
            Text(SportsArabic.league(match.league))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.80))
                .lineLimit(1)
            Spacer()
            statusPill
        }
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            if isLive { Circle().fill(AppTheme.green).frame(width: 6, height: 6) }
            Text(MatchLivePolicy.statusText(match.status, elapsed: match.elapsed).englishDigits)
                .font(.caption2.bold()).lineLimit(1).monospacedDigit()
        }
        .foregroundStyle(isLive ? AppTheme.green : AppTheme.muted)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background((isLive ? AppTheme.green.opacity(0.10) : Color.white.opacity(0.045)), in: Capsule())
    }

    private var scoreBlock: some View {
        VStack(spacing: 5) {
            if spoilerMode && !FixturePhase.isUpcoming(match.status) {
                Image(systemName: "eye.slash.fill").font(.title3).foregroundStyle(AppTheme.muted)
                Text("النتيجة مخفية").font(.caption2).foregroundStyle(AppTheme.muted)
            } else if !FixturePhase.isUpcoming(match.status), let home = match.homeScore, let away = match.awayScore {
                Text("\(home) : \(away)".englishDigits)
                    .font(.system(size: 28, weight: .black, design: .rounded)).monospacedDigit()
            } else if let date = match.date {
                Text(Self.timeFormatter.string(from: date).englishDigits)
                    .font(.system(size: 19, weight: .black, design: .rounded)).foregroundStyle(AppTheme.green).monospacedDigit()
            } else { Text("—").font(.headline) }

            if let date = match.date {
                if Calendar.current.isDateInToday(date) { Text("اليوم").font(.caption2.weight(.semibold)).foregroundStyle(AppTheme.muted) }
                else { Text(Self.dayFormatter.string(from: date).englishDigits).font(.caption2.weight(.semibold)).foregroundStyle(AppTheme.muted) }
            }
        }.frame(minWidth: 76)
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(AppTheme.cardRaised)
            if isLive { LinearGradient(colors: [AppTheme.green.opacity(0.08), Color.clear], startPoint: .topTrailing, endPoint: .bottomLeading).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous)) }
        }
    }

    private var isLive: Bool { MatchLivePolicy.isLive(match.status) }

    private func team(_ name: String, _ logo: String?) -> some View {
        VStack(spacing: 7) {
            RemoteBadge(url: logo).frame(width: 52, height: 52)
            Text(SportsArabic.team(name)).font(.caption.weight(.bold)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.72).frame(width: 102).frame(minHeight: 30)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian); f.timeZone = TimeZone(identifier: "Asia/Riyadh"); f.dateFormat = "HH:mm"; return f
    }()
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ar_SA@calendar=gregorian"); f.calendar = Calendar(identifier: .gregorian); f.timeZone = TimeZone(identifier: "Asia/Riyadh"); f.dateFormat = "d MMM"; return f
    }()
}
