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
        case "المنتهية": base = matches.filter { isFinished($0) }
        case "متابعة": base = matches.filter { followed.contains($0.id) }
        default: base = matches
        }
        return base
    }

    private var grouped: [(String, [LiveMatch])] {
        Dictionary(grouping: filtered, by: \.league)
            .map { league, items in
                (league, items.sorted { matchSortValue($0) < matchSortValue($1) })
            }
            .sorted { lhs, rhs in
                let lp = leaguePriority(lhs.0), rp = leaguePriority(rhs.0)
                return lp == rp ? lhs.0 < rhs.0 : lp > rp
            }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        TopBar(title: "المباريات")
                        matchSummary
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
                .task {
                    await loadSelectedDate()
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(30))
                        if Calendar.current.isDateInToday(selectedDate) { await loadSelectedDate(silent: true) }
                    }
                }
                .onChange(of: selectedDate) { _, _ in Task { await loadSelectedDate() } }

                if let alert = store.liveAlert {
                    liveToast(alert)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(10)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: store.liveAlert)
        }
    }

    private var matchSummary: some View {
        HStack(spacing: 10) {
            summaryChip(title: "المباريات", value: "\(matches.count)", icon: "soccerball")
            summaryChip(title: "مباشر", value: "\(matches.filter(isLive).count)", icon: "dot.radiowaves.left.and.right")
            summaryChip(title: "متابعة", value: "\(matches.filter { followed.contains($0.id) }.count)", icon: "bell.fill")
        }
        .padding(.horizontal, 16)
    }

    private func summaryChip(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).foregroundStyle(AppTheme.green)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.headline.bold()).foregroundStyle(.white)
                Text(title).font(.caption2).foregroundStyle(AppTheme.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 15))
    }

    private var dateStrip: some View {
        HStack(spacing: 8) {
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
                }
            }

            if !Calendar.current.isDateInToday(selectedDate) {
                Button {
                    selectedDate = Calendar.current.startOfDay(for: Date())
                } label: {
                    Image(systemName: "scope")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(width: 44, height: 58)
                        .background(AppTheme.green, in: RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("العودة إلى مباريات اليوم")
            }
        }
        .padding(.horizontal, 16)
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
                statusBadge(m)
                Spacer()
                Button { toggleFollow(m.id) } label: {
                    Image(systemName: followed.contains(m.id) ? "bell.fill" : "bell")
                        .foregroundStyle(followed.contains(m.id) ? AppTheme.green : AppTheme.muted)
                        .frame(width: 34, height: 34)
                        .background(AppTheme.soft, in: Circle())
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
                    Text(centerCaption(m)).font(.caption2).foregroundStyle(AppTheme.muted)
                    if followed.contains(m.id) { Text("متابعة مفعلة").font(.caption2.bold()).foregroundStyle(AppTheme.green) }
                }
                Spacer()
                team(name: m.away, badge: m.awayBadge)
            }
        }
        .padding(15)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(isLive(m) ? AppTheme.green.opacity(0.55) : Color.clear, lineWidth: 1))
        .padding(.horizontal, 16)
    }

    @ViewBuilder private func statusBadge(_ m: LiveMatch) -> some View {
        if isLive(m) {
            HStack(spacing: 5) {
                Circle().fill(AppTheme.green).frame(width: 7, height: 7)
                Text(localizedStatus(m.status, fallback: "مباشر")).font(.caption2.bold())
            }
            .foregroundStyle(AppTheme.green)
        } else if isFinished(m) {
            Text("انتهت").font(.caption2.bold()).foregroundStyle(AppTheme.muted)
        } else {
            Text(localizedStatus(m.status, fallback: "قادمة")).font(.caption2).foregroundStyle(AppTheme.muted)
        }
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

    private func liveToast(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.fill").foregroundStyle(.black)
                .frame(width: 34, height: 34)
                .background(AppTheme.green, in: Circle())
            Text(text).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(2)
            Spacer()
            Button { store.clearLiveAlert() } label: {
                Image(systemName: "xmark").foregroundStyle(AppTheme.muted)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppTheme.green.opacity(0.35), lineWidth: 1))
        .task {
            try? await Task.sleep(for: .seconds(6))
            if store.liveAlert == text { store.clearLiveAlert() }
        }
    }

    @MainActor private func loadSelectedDate(silent: Bool = false) async {
        if !silent { loading = true }
        if Calendar.current.isDateInToday(selectedDate) && !store.matches.isEmpty { matches = store.matches }
        do {
            matches = try await store.matches(on: selectedDate)
            if Calendar.current.isDateInToday(selectedDate) {
                store.matches = matches
                store.lastUpdated = Date()
            }
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
        if s.contains("live") || s.contains("1h") || s.contains("2h") || s.contains("half") || s.contains("in progress") || s.contains("ht") { return true }
        return false
    }

    private func isFinished(_ m: LiveMatch) -> Bool {
        let s = m.status.lowercased()
        return s.contains("finished") || s == "ft" || s.contains("after extra time") || s.contains("after penalties")
    }

    private func centerCaption(_ m: LiveMatch) -> String {
        if isLive(m) { return localizedStatus(m.status, fallback: "الآن") }
        if isFinished(m) { return "النتيجة النهائية" }
        if m.homeScore != nil && m.awayScore != nil { return "النتيجة" }
        return "موعد المباراة"
    }

    private func localizedStatus(_ status: String, fallback: String) -> String {
        let s = status.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return fallback }
        let lower = s.lowercased()
        if lower == "ft" || lower.contains("finished") { return "انتهت" }
        if lower == "ht" || lower.contains("half time") { return "بين الشوطين" }
        if lower.contains("not started") || lower.contains("scheduled") { return "قادمة" }
        if lower.contains("postpon") { return "مؤجلة" }
        if lower.contains("cancel") { return "ملغاة" }
        if lower.contains("extra time") { return "وقت إضافي" }
        if lower.contains("penalt") { return "ركلات ترجيح" }
        return s
    }

    private func matchSortValue(_ m: LiveMatch) -> String {
        if isLive(m) { return "0-\(m.time)" }
        if !isFinished(m) { return "1-\(m.time)" }
        return "2-\(m.time)"
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
