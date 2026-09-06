import SwiftUI

struct V2HomeView: View {
    @StateObject private var api = APISportsStore.shared
    @StateObject private var content = SportsStore.shared

    private var live: [APIPlusMatch] { api.today.filter { api.isLive($0.status) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    TopBar(title: nil, showsLogo: true)
                    if !APIFootballClient.hasKey { setupCard } else {
                        liveHero
                        todaySection
                        quickActions
                        newsSection
                    }
                }.padding(.bottom, 28)
            }
            .background(AppTheme.bg.ignoresSafeArea())
            .refreshable {
                async let a: Void = api.refreshToday(force: true)
                async let b: Void = content.refresh()
                _ = await (a, b)
            }
            .task {
                async let a: Void = api.refreshToday()
                async let b: Void = content.refreshIfStale(maxAge: 180)
                _ = await (a, b)
            }
        }
    }

    @ViewBuilder private var liveHero: some View {
        if let match = live.first ?? api.today.first {
            NavigationLink { V2MatchCenterView(match: match) } label: {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label(live.isEmpty ? "أبرز مباراة" : "مباشر الآن", systemImage: live.isEmpty ? "star.fill" : "dot.radiowaves.left.and.right")
                            .font(.caption.bold()).foregroundStyle(live.isEmpty ? AppTheme.muted : AppTheme.green)
                        Spacer(); Text(match.league).font(.caption).foregroundStyle(AppTheme.muted).lineLimit(1)
                    }
                    HStack(spacing: 14) {
                        heroTeam(match.home, match.homeLogo); Spacer()
                        VStack(spacing: 5) {
                            if let h = match.homeScore, let a = match.awayScore { Text("\(h) - \(a)").font(.system(size: 31, weight: .black, design: .rounded)) }
                            else if let date = match.date { Text(date, style: .time).font(.title2.bold()) }
                            Text(statusArabic(match.status, elapsed: match.elapsed)).font(.caption.bold()).foregroundStyle(AppTheme.green)
                        }
                        Spacer(); heroTeam(match.away, match.awayLogo)
                    }
                }
                .foregroundStyle(.white).padding(18)
                .background(LinearGradient(colors: [AppTheme.card, AppTheme.green.opacity(0.12)], startPoint: .topTrailing, endPoint: .bottomLeading), in: RoundedRectangle(cornerRadius: 24))
                .overlay { RoundedRectangle(cornerRadius: 24).stroke(AppTheme.green.opacity(live.isEmpty ? 0.12 : 0.3), lineWidth: 1) }
                .padding(.horizontal, 16)
            }.buttonStyle(.plain)
        }
    }

    private var todaySection: some View {
        VStack(spacing: 10) {
            sectionHeader("مباريات اليوم", subtitle: "\(api.today.count) مباراة")
            if api.loading && api.today.isEmpty { ProgressView().tint(AppTheme.green).padding(30) }
            else if api.today.isEmpty { emptyCard("لا توجد مباريات متاحة اليوم", icon: "soccerball") }
            else {
                ForEach(Array(api.today.prefix(6))) { match in
                    NavigationLink { V2MatchCenterView(match: match) } label: { APICompactMatchCard(match: match) }.buttonStyle(.plain)
                }
            }
        }
    }

    private var quickActions: some View {
        VStack(spacing: 10) {
            sectionHeader("استكشف 90+", subtitle: nil)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    NavigationLink { APIDiscoverView() } label: { quickCard("بحث", icon: "magnifyingglass") }
                    NavigationLink { APIStandingsView(league: LeagueOption.featured[0]) } label: { quickCard("الدوري السعودي", icon: "list.number") }
                    NavigationLink { EnhancedTransfersView() } label: { quickCard("الانتقالات", icon: "arrow.left.arrow.right") }
                    NavigationLink { V2MatchesView() } label: { quickCard("كل المباريات", icon: "calendar") }
                }.padding(.horizontal, 16)
            }.buttonStyle(.plain)
        }
    }

    private var newsSection: some View {
        VStack(spacing: 10) {
            sectionHeader("آخر الأخبار", subtitle: "مصادر حقيقية")
            if content.news.isEmpty { emptyCard("جاري جلب آخر الأخبار", icon: "newspaper") }
            else {
                ForEach(Array(content.news.prefix(4))) { article in
                    Link(destination: article.url ?? URL(string: "https://news.google.com")!) {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 12).fill(AppTheme.green.opacity(0.12)).frame(width: 52, height: 52).overlay { Image(systemName: "newspaper.fill").foregroundStyle(AppTheme.green) }
                            VStack(alignment: .leading, spacing: 5) {
                                Text(article.title).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(2)
                                HStack(spacing: 6) { Text(article.source); Text("•"); Text(article.date, style: .relative) }.font(.caption2).foregroundStyle(AppTheme.muted)
                            }
                            Spacer(minLength: 0)
                        }.padding(12).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    private var setupCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "bolt.horizontal.circle.fill").font(.system(size: 46)).foregroundStyle(AppTheme.green)
            Text("تفعيل البيانات الرياضية").font(.title2.bold())
            Text("هذه خطوة مؤقتة أثناء التطوير. في النسخة النهائية سيعمل 90+ مباشرة بدون أي إعداد من المستخدم.").font(.subheadline).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
        }.padding(24).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 24)).padding(.horizontal, 16)
    }

    private func sectionHeader(_ title: String, subtitle: String?) -> some View { HStack(alignment: .firstTextBaseline) { Text(title).font(.title3.bold()); Spacer(); if let subtitle { Text(subtitle).font(.caption).foregroundStyle(AppTheme.muted) } }.padding(.horizontal, 16) }
    private func heroTeam(_ name: String, _ logo: String?) -> some View { VStack(spacing: 7) { RemoteBadge(url: logo).frame(width: 64, height: 64); Text(name).font(.subheadline.bold()).multilineTextAlignment(.center).lineLimit(2).frame(width: 100) } }
    private func quickCard(_ title: String, icon: String) -> some View { VStack(spacing: 9) { Image(systemName: icon).font(.title2.bold()).foregroundStyle(AppTheme.green); Text(title).font(.caption.bold()).foregroundStyle(.white).lineLimit(1) }.frame(width: 112, height: 88).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)) }
    private func emptyCard(_ text: String, icon: String) -> some View { Label(text, systemImage: icon).font(.subheadline).foregroundStyle(AppTheme.muted).frame(maxWidth: .infinity).padding(22).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16) }
    private func statusArabic(_ status: String, elapsed: Int?) -> String { let s=status.uppercased(); if api.isLive(s) { return elapsed.map { "مباشر • \($0)′" } ?? "مباشر" }; switch s { case "FT": return "انتهت"; case "HT": return "بين الشوطين"; case "NS": return "لم تبدأ"; case "PST": return "مؤجلة"; case "CANC": return "ملغاة"; case "AET": return "انتهت بعد وقت إضافي"; case "PEN": return "انتهت بركلات الترجيح"; default: return status.isEmpty ? "موعد" : status } }
}
