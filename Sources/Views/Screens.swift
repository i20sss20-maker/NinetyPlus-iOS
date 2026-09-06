import SwiftUI

struct MatchesView: View {
    @State private var segment = "الكل"
    @StateObject private var store = SportsStore.shared

    private var filtered: [LiveMatch] {
        switch segment {
        case "مباشر": return store.matches.filter { !$0.status.isEmpty && !$0.status.lowercased().contains("not started") }
        case "المنتهية": return store.matches.filter { $0.homeScore != nil && $0.awayScore != nil }
        case "القادمة": return store.matches.filter { $0.homeScore == nil && $0.awayScore == nil }
        default: return store.matches
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    TopBar(title: "المباريات")
                    SegmentBar(items: ["الكل", "مباشر", "القادمة", "المنتهية"], selected: $segment)

                    if store.isLoading && store.matches.isEmpty {
                        ProgressView("جاري تحديث المباريات...")
                            .tint(AppTheme.green).foregroundStyle(.white).padding(.top, 70)
                    } else if filtered.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "soccerball").font(.system(size: 44)).foregroundStyle(AppTheme.green)
                            Text("لا توجد مباريات في هذا القسم الآن").foregroundStyle(AppTheme.muted)
                        }.padding(.top, 70)
                    } else {
                        ForEach(filtered) { match in
                            NavigationLink {
                                MatchDetailView(match: match)
                            } label: {
                                matchCard(match)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }.padding(.bottom, 24)
            }
            .refreshable { await store.refresh() }
            .task {
                if store.matches.isEmpty { await store.refresh() }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    await store.refresh()
                }
            }
            .background(AppTheme.bg.ignoresSafeArea())
        }
    }

    private func matchCard(_ m: LiveMatch) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(m.league).font(.caption).foregroundStyle(AppTheme.muted).lineLimit(1)
                Spacer()
                if !m.status.isEmpty {
                    Text(m.status).font(.caption2.bold()).foregroundStyle(AppTheme.green)
                }
            }
            HStack(spacing: 14) {
                team(name: m.home, badge: m.homeBadge)
                Spacer()
                VStack(spacing: 5) {
                    if let hs = m.homeScore, let ascore = m.awayScore {
                        Text("\(hs) - \(ascore)").font(.title2.bold())
                    } else {
                        Text(m.time).font(.headline).foregroundStyle(AppTheme.green)
                    }
                    Text(m.homeScore == nil ? "موعد المباراة" : "النتيجة")
                        .font(.caption2).foregroundStyle(AppTheme.muted)
                }
                Spacer()
                team(name: m.away, badge: m.awayBadge)
            }
        }
        .padding(16)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 16)
    }

    private func team(name: String, badge: String?) -> some View {
        VStack(spacing: 6) {
            RemoteBadge(url: badge).frame(width: 44, height: 44)
            Text(name).font(.caption.bold()).multilineTextAlignment(.center).lineLimit(2).frame(maxWidth: 95)
        }
    }
}

struct MatchDetailView: View {
    let match: LiveMatch
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text(match.league).font(.headline).foregroundStyle(AppTheme.muted)
                HStack(spacing: 20) {
                    club(match.home, match.homeBadge)
                    Spacer()
                    VStack(spacing: 6) {
                        if let hs = match.homeScore, let ascore = match.awayScore {
                            Text("\(hs) - \(ascore)").font(.system(size: 38, weight: .black))
                        } else {
                            Text(match.time).font(.title2.bold()).foregroundStyle(AppTheme.green)
                        }
                        if !match.status.isEmpty { Text(match.status).font(.caption).foregroundStyle(AppTheme.green) }
                    }
                    Spacer()
                    club(match.away, match.awayBadge)
                }
                .padding(20)
                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))

                VStack(alignment: .leading, spacing: 12) {
                    Label("البيانات المعروضة تأتي مباشرة من مزود المباريات.", systemImage: "checkmark.shield.fill")
                        .foregroundStyle(AppTheme.green)
                    Text("لن نعرض إحصائيات أو تشكيلات تقديرية. عند توفرها من المصدر ستظهر هنا تلقائيًا.")
                        .font(.subheadline).foregroundStyle(AppTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
            }
            .padding(16)
        }
        .navigationTitle("تفاصيل المباراة")
        .navigationBarTitleDisplayMode(.inline)
        .background(AppTheme.bg.ignoresSafeArea())
    }

    private func club(_ name: String, _ badge: String?) -> some View {
        VStack(spacing: 8) {
            RemoteBadge(url: badge).frame(width: 66, height: 66)
            Text(name).font(.headline).multilineTextAlignment(.center).frame(maxWidth: 105)
        }
    }
}

struct NewsView: View {
    @StateObject private var store = SportsStore.shared
    @State private var query = ""

    private var items: [RealArticle] {
        guard !query.isEmpty else { return store.news }
        return store.news.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.source.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    TopBar(title: "الأخبار")
                    if items.isEmpty && !store.isLoading {
                        Text("لا توجد نتائج").foregroundStyle(AppTheme.muted).padding(.top, 60)
                    }
                    ForEach(items) { item in articleCard(item) }
                }.padding(.bottom, 24)
            }
            .searchable(text: $query, prompt: "ابحث في الأخبار")
            .refreshable { await store.refresh() }
            .task { if store.news.isEmpty { await store.refresh() } }
            .background(AppTheme.bg.ignoresSafeArea())
        }
    }

    private func articleCard(_ item: RealArticle) -> some View {
        Link(destination: item.url ?? URL(string: "https://news.google.com")!) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "newspaper.fill").foregroundStyle(AppTheme.green)
                    Text(item.source.isEmpty ? "مصدر إخباري" : item.source).font(.caption.bold()).foregroundStyle(AppTheme.green)
                    Spacer()
                    Text(item.date, style: .relative).font(.caption2).foregroundStyle(AppTheme.muted)
                }
                Text(item.title).font(.headline).foregroundStyle(.white).multilineTextAlignment(.leading)
                HStack { Spacer(); Image(systemName: "arrow.up.right.square").foregroundStyle(AppTheme.muted) }
            }
            .padding(15)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 16)
        }
    }
}

struct TransfersView: View {
    @StateObject private var store = SportsStore.shared
    @State private var query = ""

    private var items: [RealArticle] {
        guard !query.isEmpty else { return store.transfers }
        return store.transfers.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    TopBar(title: "مركز الانتقالات")
                    Text("أخبار انتقالات فعلية من المصادر — بدون نسب أو صفقات مختلقة")
                        .font(.caption).foregroundStyle(AppTheme.muted).padding(.horizontal, 16)
                    ForEach(items) { item in
                        Link(destination: item.url ?? URL(string: "https://news.google.com")!) {
                            VStack(alignment: .leading, spacing: 9) {
                                HStack {
                                    Text(item.source.isEmpty ? "مصدر إخباري" : item.source)
                                        .font(.caption.bold()).foregroundStyle(AppTheme.green)
                                    Spacer()
                                    Text(item.date, style: .relative).font(.caption2).foregroundStyle(AppTheme.muted)
                                }
                                Text(item.title).font(.headline).foregroundStyle(.white).multilineTextAlignment(.leading)
                                Label("فتح المصدر", systemImage: "link").font(.caption).foregroundStyle(AppTheme.muted)
                            }
                            .padding(15)
                            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
                            .padding(.horizontal, 16)
                        }
                    }
                }.padding(.bottom, 24)
            }
            .searchable(text: $query, prompt: "ابحث في الانتقالات")
            .refreshable { await store.refresh() }
            .task { if store.transfers.isEmpty { await store.refresh() } }
            .background(AppTheme.bg.ignoresSafeArea())
        }
    }
}

struct ProfileView: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("favoriteLeague") private var favoriteLeague = "الدوري السعودي"

    var body: some View {
        NavigationStack {
            Form {
                Section("90+") {
                    HStack {
                        BrandLogo()
                        Spacer()
                        Text("نسخة تجريبية حقيقية البيانات").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("التفضيلات") {
                    Toggle("الإشعارات", isOn: $notificationsEnabled)
                    Picker("الدوري المفضل", selection: $favoriteLeague) {
                        Text("الدوري السعودي").tag("الدوري السعودي")
                        Text("دوري أبطال أوروبا").tag("دوري أبطال أوروبا")
                        Text("الدوري الإنجليزي").tag("الدوري الإنجليزي")
                        Text("الدوري الإسباني").tag("الدوري الإسباني")
                    }
                }
                Section("البيانات") {
                    Label("المباريات: TheSportsDB", systemImage: "soccerball")
                    Label("الأخبار: Google News RSS", systemImage: "newspaper")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.bg)
            .navigationTitle("حسابي")
        }
    }
}
