import SwiftUI

struct MatchesView: View {
    @State private var segment = "الكل"
    @StateObject private var store = SportsStore.shared

    var filtered: [LiveMatch] {
        switch segment {
        case "المنتهية": return store.matches.filter { $0.homeScore != nil && $0.awayScore != nil }
        case "القادمة": return store.matches.filter { $0.homeScore == nil && $0.awayScore == nil }
        default: return store.matches
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                TopBar(title: "المباريات")
                SegmentBar(items: ["الكل", "القادمة", "المنتهية"], selected: $segment)
                if store.isLoading && store.matches.isEmpty {
                    ProgressView("جاري جلب مباريات اليوم...").tint(AppTheme.green).foregroundStyle(.white).padding(.top, 60)
                } else if filtered.isEmpty {
                    Text("لا توجد مباريات ضمن هذا القسم اليوم").foregroundStyle(AppTheme.muted).padding(.top, 60)
                } else {
                    ForEach(filtered) { match in matchCard(match) }
                }
            }.padding(.bottom, 24)
        }
        .refreshable { await store.refresh() }
        .task { if store.matches.isEmpty { await store.refresh() } }
        .background(AppTheme.bg.ignoresSafeArea())
    }

    private func matchCard(_ m: LiveMatch) -> some View {
        VStack(spacing: 14) {
            HStack {
                Text(m.league).font(.caption.bold()).foregroundStyle(AppTheme.muted)
                Spacer()
                Text(m.status.isEmpty ? "اليوم" : m.status).font(.caption).foregroundStyle(AppTheme.green)
            }
            HStack(spacing: 12) {
                VStack(spacing: 8) {
                    RemoteBadge(url: m.homeBadge).frame(width: 48, height: 48)
                    Text(m.home).font(.subheadline.bold()).multilineTextAlignment(.center).lineLimit(2)
                }.frame(maxWidth: .infinity)

                VStack(spacing: 6) {
                    if let hs = m.homeScore, let ascore = m.awayScore {
                        Text("\(hs) - \(ascore)").font(.system(size: 30, weight: .bold))
                    } else {
                        Text(m.time).font(.headline).foregroundStyle(AppTheme.green)
                    }
                }

                VStack(spacing: 8) {
                    RemoteBadge(url: m.awayBadge).frame(width: 48, height: 48)
                    Text(m.away).font(.subheadline.bold()).multilineTextAlignment(.center).lineLimit(2)
                }.frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 16)
    }
}

struct NewsView: View {
    @StateObject private var store = SportsStore.shared
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                TopBar(title: "الأخبار")
                if store.isLoading && store.news.isEmpty {
                    ProgressView("جاري التحديث...").tint(AppTheme.green).foregroundStyle(.white).padding(.top, 60)
                }
                ForEach(store.news) { item in articleCard(item) }
            }.padding(.bottom, 24)
        }
        .refreshable { await store.refresh() }
        .task { if store.news.isEmpty { await store.refresh() } }
        .background(AppTheme.bg.ignoresSafeArea())
    }

    private func articleCard(_ item: RealArticle) -> some View {
        Link(destination: item.url ?? URL(string: "https://news.google.com")!) {
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 14).fill(AppTheme.soft).frame(height: 120)
                    .overlay(Image(systemName: "newspaper.fill").font(.system(size: 44)).foregroundStyle(AppTheme.green))
                Text(item.title).font(.headline).foregroundStyle(.white).multilineTextAlignment(.leading)
                HStack {
                    Text(item.source.isEmpty ? "مصدر إخباري" : item.source)
                    Spacer()
                    Text(item.date, style: .relative)
                }.font(.caption).foregroundStyle(AppTheme.muted)
            }.padding(14).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
        }
    }
}

struct TransfersView: View {
    @State private var segment = "الكل"
    @StateObject private var store = SportsStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                TopBar(title: "مركز الانتقالات")
                SegmentBar(items: ["الكل", "آخر الأخبار", "السعودية"], selected: $segment)
                if store.isLoading && store.transfers.isEmpty {
                    ProgressView("جاري جلب أخبار الانتقالات...").tint(AppTheme.green).foregroundStyle(.white).padding(.top, 60)
                }
                ForEach(store.transfers) { item in transferCard(item) }
            }.padding(.bottom, 24)
        }
        .refreshable { await store.refresh() }
        .task { if store.transfers.isEmpty { await store.refresh() } }
        .background(AppTheme.bg.ignoresSafeArea())
    }

    private func transferCard(_ item: RealArticle) -> some View {
        Link(destination: item.url ?? URL(string: "https://news.google.com")!) {
            HStack(spacing: 14) {
                Circle().fill(AppTheme.soft).frame(width: 70, height: 70)
                    .overlay(Image(systemName: "arrow.left.arrow.right.circle.fill").font(.system(size: 38)).foregroundStyle(AppTheme.green))
                VStack(alignment: .leading, spacing: 7) {
                    Text("90+ TRANSFERS").font(.caption2.bold()).foregroundStyle(.black)
                        .padding(.horizontal, 8).padding(.vertical, 4).background(AppTheme.green, in: Capsule())
                    Text(item.title).font(.headline).foregroundStyle(.white).lineLimit(3)
                    HStack {
                        Text(item.source.isEmpty ? "مصدر إخباري" : item.source)
                        Text("•")
                        Text(item.date, style: .relative)
                    }.font(.caption).foregroundStyle(AppTheme.muted)
                }
                Spacer()
            }
            .padding(14).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
        }
    }
}

struct ProfileView: View {
    var body: some View {
        VStack(spacing: 18) {
            TopBar(title: "حسابي")
            Spacer()
            BrandLogo()
            Text("90+ نايـنتي بلس").font(.title2.bold())
            Text("الأخبار • مباريات اليوم • الانتقالات • مصادر مباشرة").foregroundStyle(AppTheme.muted).multilineTextAlignment(.center).padding(.horizontal)
            Spacer()
        }.background(AppTheme.bg.ignoresSafeArea())
    }
}
