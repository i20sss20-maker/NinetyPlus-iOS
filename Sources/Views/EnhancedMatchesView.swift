import SwiftUI

struct EnhancedMatchesView: View {
    @StateObject private var store = SportsStore.shared
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var matches: [LiveMatch] = []
    @State private var loading = false
    @State private var segment = "الكل"
    @AppStorage("followedMatchIDs") private var followedMatchIDs = ""

    private var days: [Date] {
        (-3...3).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: Calendar.current.startOfDay(for: Date())) }
    }

    private var followed: Set<String> {
        Set(followedMatchIDs.split(separator: ",").map(String.init))
    }

    private var filtered: [LiveMatch] {
        let base: [LiveMatch]
        switch segment {
        case "مباشر": base = matches.filter { isLive($0) }
        case "القادمة": base = matches.filter { $0.homeScore == nil && $0.awayScore == nil && !isLive($0) }
        case "المنتهية": base = matches.filter { $0.homeScore != nil && $0.awayScore != nil && !isLive($0) }
        case "متابعة": base = matches.filter { followed.contains($0.id) }
        default: base = matches
        }
        return base
    }

    private var grouped: [(String, [LiveMatch])] {
        Dictionary(grouping: filtered, by: \.league)
            .map { ($0.key, $0.value) }
            .sorted { lhs, rhs in
                let lp = leaguePriority(lhs.0), rp = leaguePriority(rhs.0)
                return lp == rp ? lhs.0 < rhs.0 : lp > rp
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    TopBar(title: "المباريات")
                    dateStrip
                    SegmentBar(items: ["الكل", "مباشر", "القادمة", "المنتهية", "متابعة"], selected: $segment)

                    if loading && matches.isEmpty {
                        ProgressView("جاري تحميل المباريات...").tint(AppTheme.green).padding(.top, 60)
                    } else if filtered.isEmpty {
                        emptyState
                    } else {
                        ForEach(grouped, id: \.0) { league, items in
                            leagueHeader(league, count: items.count)
                            ForEach(items) { match in
                                NavigationLink { MatchDetailView(match: match) } label: { matchCard(match) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }.padding(.bottom, 30)
            }
            .background(AppTheme.bg.ignoresSafeArea())
            .refreshable { await loadSelectedDate() }
            .task { await loadSelectedDate() }
            .onChange(of: selectedDate) { _, _ in Task { await loadSelectedDate() } }
        }
    }

    private var dateStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(days, id: \.self) { day in
                    Button { selectedDate = day } label: {
                        VStack(spacing: 4) {
                            Text(dayTitle(day)).font(.caption.bold())
                            Text(day.formatted(.dateTime.day())).font(.headline)
                        }
                        .foregroundStyle(Calendar.current.isDate(day, inSameDayAs: selectedDate) ? .black : .white)
                        .frame(width: 58, height: 58)
                        .background(Calendar.current.isDate(day, inSameDayAs: selectedDate) ? AppTheme.green : AppTheme.card, in: RoundedRectangle(cornerRadius: 15))
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 16)
        }
    }

    private func leagueHeader(_ league: String, count: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(league).font(.headline)
                Text("\(count) مباراة").font(.caption2).foregroundStyle(AppTheme.muted)
            }
            Spacer()
            Image(systemName: "trophy.fill").foregroundStyle(AppTheme.green)
        }.padding(.horizontal, 16).padding(.top, 4)
    }

    private func matchCard(_ m: LiveMatch) -> some View {
        VStack(spacing: 12) {
            HStack {
                if isLive(m) {
                    Label("مباشر", systemImage: "dot.radiowaves.left.and.right").font(.caption2.bold()).foregroundStyle(AppTheme.green)
                } else if !m.status.isEmpty {
                    Text(m.status).font(.caption2).foregroundStyle(AppTheme.muted)
                }
                Spacer()
                Button { toggleFollow(m.id) } label: {
                    Image(systemName: followed.contains(m.id) ? "bell.fill" : "bell")
                        .foregroundStyle(followed.contains(m.id) ? AppTheme.green : AppTheme.muted)
                }.buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                team(name: m.home, badge: m.homeBadge)
                Spacer()
                VStack(spacing: 4) {
                    if let hs = m.homeScore, let ascore = m.awayScore {
                        Text("\(hs)  -  \(ascore)").font(.title2.bold())
                    } else {
                        Text(m.time).font(.headline).foregroundStyle(AppTheme.green)
                    }
                    if followed.contains(m.id) { Text("تتابع هذه المباراة").font(.caption2).foregroundStyle(AppTheme.green) }
                }
                Spacer()
                team(name: m.away, badge: m.awayBadge)
            }
        }
        .padding(15)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(isLive(m) ? AppTheme.green.opacity(0.45) : Color.clear, lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private func team(name: String, badge: String?) -> some View {
        VStack(spacing: 6) {
            RemoteBadge(url: badge).frame(width: 42, height: 42)
            Text(name).font(.caption.bold()).multilineTextAlignment(.center).lineLimit(2).frame(maxWidth: 95)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: segment == "متابعة" ? "bell.slash" : "calendar.badge.exclamationmark")
                .font(.system(size: 42)).foregroundStyle(AppTheme.green)
            Text(segment == "متابعة" ? "ما عندك مباريات متابعة في هذا اليوم" : "لا توجد مباريات في هذا القسم")
                .foregroundStyle(AppTheme.muted)
            if segment == "متابعة" { Text("اضغط الجرس بجانب أي مباراة عشان تجمعها هنا").font(.caption).foregroundStyle(AppTheme.muted) }
        }.padding(.top, 70)
    }

    @MainActor private func loadSelectedDate() async {
        loading = true
        if Calendar.current.isDateInToday(selectedDate) && !store.matches.isEmpty { matches = store.matches }
        do {
            matches = try await store.matches(on: selectedDate)
            if Calendar.current.isDateInToday(selectedDate) { store.matches = matches }
        } catch {
            if matches.isEmpty && Calendar.current.isDateInToday(selectedDate) { matches = store.matches }
        }
        loading = false
    }

    private func toggleFollow(_ id: String) {
        var ids = followed
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        followedMatchIDs = ids.sorted().joined(separator: ",")
    }

    private func isLive(_ m: LiveMatch) -> Bool {
        let s = m.status.lowercased()
        if s.contains("live") || s.contains("1h") || s.contains("2h") || s.contains("half") || s.contains("in progress") { return true }
        if let hs = m.homeScore, let ascore = m.awayScore, !hs.isEmpty, !ascore.isEmpty, !s.contains("finished") && !s.contains("ft") { return true }
        return false
    }

    private func dayTitle(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "اليوم" }
        if Calendar.current.isDateInYesterday(date) { return "أمس" }
        if Calendar.current.isDateInTomorrow(date) { return "غدًا" }
        let df = DateFormatter(); df.locale = Locale(identifier: "ar_SA"); df.dateFormat = "EEE"; return df.string(from: date)
    }

    private func leaguePriority(_ name: String) -> Int {
        let n = name.lowercased()
        if n.contains("saudi") || n.contains("روشن") { return 100 }
        if n.contains("champions") { return 90 }
        if n.contains("premier") { return 80 }
        if n.contains("laliga") || n.contains("la liga") { return 70 }
        if n.contains("serie a") || n.contains("bundesliga") || n.contains("ligue 1") { return 60 }
        return 10
    }
}
