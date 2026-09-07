import SwiftUI

struct APICompactMatchCard: View {
    let match: APIPlusMatch

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                if let leagueLogo = match.leagueLogo {
                    RemoteBadge(url: leagueLogo).frame(width: 24, height: 24)
                }
                Text(SportsArabic.league(match.league))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                Spacer()
                HStack(spacing: 5) {
                    if isLive {
                        Circle().fill(AppTheme.green).frame(width: 6, height: 6)
                    }
                    Text(MatchLivePolicy.statusText(match.status, elapsed: match.elapsed))
                        .font(.caption.bold())
                }
                .foregroundStyle(isLive ? AppTheme.green : AppTheme.muted)
            }

            HStack(spacing: 10) {
                team(match.home, match.homeLogo)
                Spacer(minLength: 8)
                VStack(spacing: 5) {
                    if !FixturePhase.isUpcoming(match.status), let home = match.homeScore, let away = match.awayScore {
                        Text("\(home)  -  \(away)")
                            .font(.system(size: 25, weight: .black, design: .rounded))
                            .monospacedDigit()
                    } else if let date = match.date {
                        Text(date, style: .time)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.green)
                    } else {
                        Text("—").font(.headline)
                    }
                    if let date = match.date, !Calendar.current.isDateInToday(date) {
                        Text(date.formatted(.dateTime.day().month(.abbreviated)))
                            .font(.caption2).foregroundStyle(AppTheme.muted)
                    }
                }
                .frame(minWidth: 78)
                Spacer(minLength: 8)
                team(match.away, match.awayLogo)
            }
        }
        .foregroundStyle(.white)
        .padding(15)
        .background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppTheme.border, lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private var isLive: Bool { MatchLivePolicy.isLive(match.status) }

    private func team(_ name: String, _ logo: String?) -> some View {
        VStack(spacing: 7) {
            RemoteBadge(url: logo).frame(width: 48, height: 48)
            Text(SportsArabic.team(name))
                .font(.caption.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .frame(width: 100)
        }
    }
}
