import SwiftUI

/// Native table from a separately identified public source. No API-Football ID
/// is inferred from an ESPN name or ID. The returned season dates are validated.
struct PublicLeagueTableView: View {
    let league: LeagueOption
    var teamsOnly = false
    var refreshID = 0
    @State private var resource = PageResource<PublicLeagueTable>()
    @State private var retry = 0
    private var code: String { PublicLeagueSource.code(for: league.apiFootballID) ?? "" }

    var body: some View {
        VStack(spacing: 14) {
            if resource.isLoading && resource.value == nil {
                ProgressView("جارٍ تحميل ترتيب الموسم الحالي…").font(.caption).tint(AppTheme.green).padding(30)
            }
            if let message = resource.errorMessage {
                PageLoadFeedback(loading: resource.isLoading, hasValue: resource.value != nil, message: message, updatedAt: nil) { retry += 1 }
            }
            if let table = resource.value {
                sourceHeader(table)
                ForEach(Array(table.children.enumerated()), id: \.offset) { _, group in
                    if table.children.count > 1 {
                        Text(group.name ?? "المجموعة").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18)
                    }
                    if !teamsOnly { raceCards(group.standings.entries) }
                    if !teamsOnly { tableHeader }
                    LazyVStack(spacing: 0) {
                        ForEach(group.standings.entries) { entry in
                            DisclosureGroup {
                                VStack(spacing: 12) {
                                    HStack(spacing: 6) {
                                        metric("فوز", value: entry.display("wins"))
                                        metric("تعادل", value: entry.display("ties"))
                                        metric("خسارة", value: entry.display("losses"))
                                        metric("له", value: entry.display("pointsFor"))
                                        metric("عليه", value: entry.display("pointsAgainst"))
                                    }
                                    if let url = entry.sourceURL {
                                        Link(destination: url) {
                                            Label("صفحة النادي لدى ESPN", systemImage: "arrow.up.left.square")
                                                .font(.caption.bold()).foregroundStyle(AppTheme.green)
                                        }
                                    }
                                }.padding(.vertical, 12)
                            } label: {
                                row(entry)
                            }
                            .tint(AppTheme.muted)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            Divider().overlay(AppTheme.border)
                        }
                    }.background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 20)).padding(.horizontal, 16)
                }
                if table.children.allSatisfy({ $0.standings.entries.isEmpty }) {
                    Text("لم يُنشر ترتيب هذه البطولة بعد.").font(.subheadline).foregroundStyle(AppTheme.muted).padding(24)
                }
            }
        }
        .accessibilityIdentifier("league.currentTable")
        .task(id: "\(code):\(retry):\(refreshID)") { await load() }
        .onDisappear { resource.invalidate() }
    }

    @ViewBuilder private func raceCards(_ entries: [PublicLeagueTable.Entry]) -> some View {
        let ordered = entries.sorted { rankValue($0) < rankValue($1) }
        if ordered.count >= 3 {
            VStack(alignment: .leading, spacing: 10) {
                Text("صراع البطولة").font(.headline).foregroundStyle(.white)
                HStack(spacing: 10) {
                    raceCard("القمة", entries: Array(ordered.prefix(3)), icon: "trophy.fill")
                    if ordered.count >= 6 {
                        raceCard("آخر المراكز", entries: Array(ordered.suffix(3)), icon: "arrow.down.right.circle.fill")
                    }
                }
                Text("البطاقات تعرض الترتيب والنقاط المنشورة فقط، بدون توقعات.")
                    .font(.caption2).foregroundStyle(AppTheme.muted)
            }
            .padding(.horizontal, 16)
            .accessibilityIdentifier("league.raceCards")
        }
    }

    private func raceCard(_ title: String, entries: [PublicLeagueTable.Entry], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon).font(.caption.bold()).foregroundStyle(AppTheme.green)
            ForEach(entries) { entry in
                HStack(spacing: 6) {
                    Text(entry.display("rank")).font(.caption2.bold()).foregroundStyle(AppTheme.muted).frame(width: 18)
                    Text(SportsArabic.team(entry.team.displayName)).font(.caption.bold()).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(entry.display("points")).font(.caption.bold()).foregroundStyle(.white).monospacedDigit()
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.border))
    }

    private func rankValue(_ entry: PublicLeagueTable.Entry) -> Int {
        Int(entry.display("rank")) ?? Int.max
    }

    private func sourceHeader(_ table: PublicLeagueTable) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(teamsOnly ? "أندية البطولة" : "ترتيب الموسم الحالي").font(.headline).foregroundStyle(.white)
                Text("الموسم \(String(table.season.year))–\(String(table.season.year + 1))")
                    .font(.caption).foregroundStyle(AppTheme.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text("المصدر: ESPN").font(.caption.bold()).foregroundStyle(AppTheme.green)
                if let date = resource.lastUpdated {
                    Text("جُلب \(SportsDisplayDate.label(date, pattern: "HH:mm"))")
                        .font(.caption2).foregroundStyle(AppTheme.muted)
                }
            }
        }.padding(.horizontal, 20)
    }
    private var tableHeader: some View {
        HStack(spacing: 8) {
            Text("#").frame(width: 22)
            Text("النادي").frame(maxWidth: .infinity, alignment: .leading)
            Text("لعب").frame(width: 28)
            Text("الفارق").frame(width: 38)
            Text("النقاط").frame(width: 38)
            Color.clear.frame(width: 12, height: 1)
        }.font(.caption2.bold()).foregroundStyle(AppTheme.muted).padding(.horizontal, 30)
    }
    private func row(_ entry: PublicLeagueTable.Entry) -> some View {
        HStack(spacing: 8) {
            Text(entry.display("rank")).font(.caption.bold()).foregroundStyle(AppTheme.muted).frame(width: 22)
            HStack(spacing: 8) {
                RemoteBadge(url: entry.imageURL).frame(width: 30, height: 30)
                Text(SportsArabic.team(entry.team.displayName)).font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white).lineLimit(2).multilineTextAlignment(.leading)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if !teamsOnly {
                Text(entry.display("gamesPlayed")).font(.caption).frame(width: 28)
                Text(entry.display("pointDifferential")).font(.caption).frame(width: 38)
            }
            Text(entry.display("points")).font(.subheadline.bold()).foregroundStyle(AppTheme.green).frame(width: 38)
        }.foregroundStyle(.white).monospacedDigit()
    }
    private func metric(_ title: String, value: String) -> some View {
        VStack(spacing: 5) { Text(value).font(.subheadline.bold()); Text(title).font(.caption2).foregroundStyle(AppTheme.muted) }
            .frame(maxWidth: .infinity).foregroundStyle(.white)
    }
    @MainActor private func load() async {
        guard !Task.isCancelled, !code.isEmpty else { return }
        if retry == 0 && refreshID == 0 && resource.isFresh(key: code, maxAge: 600) { return }
        let token = resource.begin(key: code)
        defer { resource.cancel(token: token) }
        do {
            guard let url = URL(string: "https://site.web.api.espn.com/apis/v2/sports/soccer/\(code)/standings") else { throw PublicTableError.invalidResponse }
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count < 2_000_000 else { throw PublicTableError.unavailable }
            let table = try PublicLeagueTable.decodeCurrent(data)
            resource.succeed(table, token: token)
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            let message = (error as? PublicTableError)?.localizedDescription ?? PublicTableError.unavailable.localizedDescription
            resource.fail(message, token: token)
        }
    }
}
