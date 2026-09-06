import SwiftUI

struct HomeView: View {
    @State private var segment = "الكل"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    TopBar(title: nil, showsLogo: true)
                    SegmentBar(items: ["الكل", "أهم الأخبار", "الدوريات", "المحترفين", "تقارير خاصة"], selected: $segment)
                    hero
                    sectionHeader("آخر الأخبار")
                    ForEach(MockData.news.dropFirst()) { item in newsRow(item) }
                }
                .padding(.bottom, 24)
            }
            .background(AppTheme.bg.ignoresSafeArea())
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [AppTheme.card, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
            Image(systemName: "figure.soccer")
                .resizable().scaledToFit().frame(width: 180, height: 180)
                .foregroundStyle(.white.opacity(0.15)).offset(x: 140, y: -28)
            VStack(alignment: .leading, spacing: 10) {
                Text("حصري").font(.caption.bold()).foregroundStyle(.black).padding(.horizontal, 10).padding(.vertical, 5).background(AppTheme.green, in: Capsule())
                Text("النجم يعود بقوة").font(.title2.bold())
                Text("بعد فترة غياب طويلة.. جاهز لقيادة فريقه في المواجهة القادمة").foregroundStyle(AppTheme.muted)
            }.padding(18)
        }
        .frame(height: 270)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 16)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack { Text(title).font(.title3.bold()); Spacer(); Text("عرض الكل").foregroundStyle(AppTheme.green) }
            .padding(.horizontal, 16)
    }

    private func newsRow(_ item: NewsItem) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12).fill(AppTheme.soft).frame(width: 96, height: 74).overlay(Image(systemName: item.image).foregroundStyle(AppTheme.green))
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title).font(.headline).lineLimit(2)
                Text(item.subtitle).font(.caption).foregroundStyle(AppTheme.muted)
            }
            Spacer()
        }
        .padding(12).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 16)
    }
}
