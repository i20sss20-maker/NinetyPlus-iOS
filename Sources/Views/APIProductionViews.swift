import SwiftUI

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
                Text(MatchLivePolicy.statusText(match.status, elapsed: match.elapsed))
                    .font(.caption.bold())
                    .foregroundStyle(isLive ? AppTheme.green : AppTheme.muted)
            }

            HStack(spacing: 12) {
                team(match.home, match.homeLogo)
                Spacer()
                VStack(spacing: 4) {
                    if !FixturePhase.isUpcoming(match.status), let home = match.homeScore, let away = match.awayScore {
                        Text("\(home) - \(away)").font(.title2.bold()).monospacedDigit()
                    } else if let date = match.date {
                        Text(date, style: .time).font(.headline).foregroundStyle(AppTheme.green)
                    } else {
                        Text("—").font(.headline)
                    }
                    if let date = match.date, !Calendar.current.isDateInToday(date) {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2).foregroundStyle(AppTheme.muted)
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

    private var isLive: Bool { MatchLivePolicy.isLive(match.status) }

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
