import SwiftUI

struct HomeView: View {
    @State private var segment = "الكل"
    @StateObject private var store = SportsStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    TopBar(title: nil, showsLogo: true)
                    SegmentBar(items: ["الكل", "أهم الأخبار", "الدوري السعودي", "العالمية", "انتقالات"], selected: $segment)

                    if store.isLoading && store.news.isEmpty {
                        ProgressView("جاري جلب الأخبار الحقيقية...")
                            .tint(AppTheme.green)
                            .foregroundStyle(.white)
                            .padding(.top, 60)
                    } else if let first = store.news.first {
                        hero(first)
                        sectionHeader("آخر الأخبار")
                        ForEach(store.news.dropFirst().prefix(12)) { item in newsRow(item) }
                    } else {
                        emptyState("لا توجد أخبار متاحة الآن")
                    }
                }
                .padding(.bottom, 24)
            }
            .refreshable { await store.refresh() }
            .task { if store.news.isEmpty { await store.refresh() } }
            .background(AppTheme.bg.ignoresSafeArea())
        }
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
            .frame(height: 270)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 16)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack { Text(title).font(.title3.bold()); Spacer(); Text("تحديث مباشر").foregroundStyle(AppTheme.green).font(.caption.bold()) }
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

    private func emptyState(_ text: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 42)).foregroundStyle(AppTheme.green)
            Text(text).foregroundStyle(AppTheme.muted)
            Button("إعادة المحاولة") { Task { await store.refresh() } }.buttonStyle(.borderedProminent).tint(AppTheme.green)
        }.padding(.top, 70)
    }
}
