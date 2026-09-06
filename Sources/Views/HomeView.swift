import SwiftUI

struct HomeView: View {
    @State private var segment = "الكل"
    @StateObject private var store = SportsStore.shared

    private var liveMatches: [LiveMatch] {
        store.matches.filter { !$0.status.isEmpty && !$0.status.lowercased().contains("not started") }.prefix(3).map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    TopBar(title: nil, showsLogo: true)
                    SegmentBar(items: ["الكل", "أهم الأخبار", "الدوري السعودي", "العالمية", "انتقالات"], selected: $segment)

                    if store.isLoading && store.news.isEmpty && store.matches.isEmpty {
                        ProgressView("جاري تحديث 90+...")
                            .tint(AppTheme.green).foregroundStyle(.white).padding(.top, 60)
                    } else {
                        if !liveMatches.isEmpty {
                            sectionHeader("مباشر الآن", trailing: "LIVE")
                            ForEach(liveMatches) { match in
                                NavigationLink { MatchDetailView(match: match) } label: { liveCard(match) }.buttonStyle(.plain)
                            }
                        }

                        if let first = filteredNews.first {
                            sectionHeader("أهم الأخبار", trailing: "تحديث مباشر")
                            hero(first)
                            ForEach(filteredNews.dropFirst().prefix(8)) { item in newsRow(item) }
                        } else if segment != "انتقالات" {
                            emptyState("لا توجد أخبار متاحة الآن")
                        }

                        if segment == "الكل" || segment == "انتقالات" {
                            sectionHeader("أحدث الانتقالات", trailing: "مصادر فعلية")
                            ForEach(store.transfers.prefix(segment == "انتقالات" ? 12 : 4)) { item in transferRow(item) }
                        }

                        if segment == "الكل" {
                            quickLinks
                        }
                    }
                }
                .padding(.bottom, 28)
            }
            .refreshable { await store.refresh() }
            .task { if store.news.isEmpty || store.matches.isEmpty { await store.refresh() } }
            .background(AppTheme.bg.ignoresSafeArea())
        }
    }

    private var filteredNews: [RealArticle] {
        switch segment {
        case "الدوري السعودي": return store.news.filter { $0.title.localizedCaseInsensitiveContains("السعود") || $0.title.localizedCaseInsensitiveContains("الهلال") || $0.title.localizedCaseInsensitiveContains("النصر") || $0.title.localizedCaseInsensitiveContains("الاتحاد") || $0.title.localizedCaseInsensitiveContains("الأهلي") }
        case "العالمية": return store.news.filter { !$0.title.localizedCaseInsensitiveContains("السعود") }
        case "انتقالات": return []
        default: return store.news
        }
    }

    private func liveCard(_ m: LiveMatch) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(m.league).font(.caption).foregroundStyle(AppTheme.muted).lineLimit(1)
                Spacer()
                Text(m.status.isEmpty ? "مباشر" : m.status).font(.caption.bold()).foregroundStyle(AppTheme.green)
            }
            HStack(spacing: 10) {
                miniTeam(m.home, m.homeBadge)
                Spacer()
                VStack(spacing: 3) {
                    if let hs = m.homeScore, let ascore = m.awayScore { Text("\(hs) - \(ascore)").font(.title2.bold()) }
                    else { Text(m.time).font(.headline).foregroundStyle(AppTheme.green) }
                    Text("اضغط للتفاصيل").font(.caption2).foregroundStyle(AppTheme.muted)
                }
                Spacer()
                miniTeam(m.away, m.awayBadge)
            }
        }
        .padding(15).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
    }

    private func miniTeam(_ name: String, _ badge: String?) -> some View {
        VStack(spacing: 5) {
            RemoteBadge(url: badge).frame(width: 38, height: 38)
            Text(name).font(.caption.bold()).lineLimit(1).frame(maxWidth: 90)
        }.foregroundStyle(.white)
    }

    private func hero(_ item: RealArticle) -> some View {
        Link(destination: item.url ?? URL(string: "https://news.google.com")!) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [AppTheme.card, .black.opacity(0.95)], startPoint: .top, endPoint: .bottom)
                Image(systemName: "soccerball")
                    .resizable().scaledToFit().frame(width: 180, height: 180)
                    .foregroundStyle(.white.opacity(0.08)).offset(x: 140, y: -20)
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.source.isEmpty ? "90+ NEWS" : item.source)
                        .font(.caption.bold()).foregroundStyle(.black)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(AppTheme.green, in: Capsule())
                    Text(item.title).font(.title3.bold()).foregroundStyle(.white).lineLimit(4)
                    Text(item.date.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(AppTheme.muted).font(.caption)
                }.padding(18)
            }
            .frame(height: 245)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 16)
        }
    }

    private func sectionHeader(_ title: String, trailing: String) -> some View {
        HStack { Text(title).font(.title3.bold()); Spacer(); Text(trailing).foregroundStyle(AppTheme.green).font(.caption.bold()) }
            .padding(.horizontal, 16)
    }

    private func newsRow(_ item: RealArticle) -> some View {
        Link(destination: item.url ?? URL(string: "https://news.google.com")!) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12).fill(AppTheme.soft).frame(width: 82, height: 72)
                    .overlay(Image(systemName: "newspaper.fill").foregroundStyle(AppTheme.green).font(.title2))
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title).font(.headline).lineLimit(3).foregroundStyle(.white)
                    HStack {
                        Text(item.source.isEmpty ? "مصدر إخباري" : item.source)
                        Text("•")
                        Text(item.date, style: .relative)
                    }.font(.caption).foregroundStyle(AppTheme.muted)
                }
                Spacer()
            }
            .padding(12).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 16)
        }
    }

    private func transferRow(_ item: RealArticle) -> some View {
        Link(destination: item.url ?? URL(string: "https://news.google.com")!) {
            VStack(alignment: .leading, spacing: 7) {
                HStack { Text(item.source.isEmpty ? "مصدر إخباري" : item.source).font(.caption.bold()).foregroundStyle(AppTheme.green); Spacer(); Text(item.date, style: .relative).font(.caption2).foregroundStyle(AppTheme.muted) }
                Text(item.title).font(.headline).foregroundStyle(.white).lineLimit(3)
            }.padding(14).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 16)
        }
    }

    private var quickLinks: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("استكشف 90+", trailing: "")
            HStack(spacing: 10) {
                NavigationLink { LeaguesView() } label: { quickButton("البطولات", "trophy.fill") }
                NavigationLink { DiscoverView() } label: { quickButton("بحث", "magnifyingglass") }
                NavigationLink { FavoriteTeamsView() } label: { quickButton("المفضلة", "star.fill") }
            }.padding(.horizontal, 16)
        }
    }

    private func quickButton(_ title: String, _ icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(AppTheme.green)
            Text(title).font(.caption.bold()).foregroundStyle(.white)
        }.frame(maxWidth: .infinity).padding(.vertical, 16).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private func emptyState(_ text: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 42)).foregroundStyle(AppTheme.green)
            Text(text).foregroundStyle(AppTheme.muted)
            Button("إعادة المحاولة") { Task { await store.refresh() } }.buttonStyle(.borderedProminent).tint(AppTheme.green)
        }.padding(.top, 40)
    }
}
