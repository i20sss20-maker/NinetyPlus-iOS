import SwiftUI

struct MatchesView: View {
    @State private var segment = "الكل"
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                TopBar(title: "المباريات")
                SegmentBar(items: ["الكل", "مباشر", "القادمة", "المنتهية"], selected: $segment)
                liveCard
                ForEach(MockData.matches.dropFirst()) { match in matchRow(match) }
            }.padding(.bottom, 24)
        }.background(AppTheme.bg.ignoresSafeArea())
    }
    private var liveCard: some View {
        VStack(spacing: 18) {
            Text("مباشر").font(.caption.bold()).foregroundStyle(.black).padding(.horizontal, 12).padding(.vertical, 6).background(AppTheme.green, in: Capsule())
            HStack {
                team("النسر", icon: "shield.fill")
                Spacer()
                VStack { Text("2 - 1").font(.system(size: 42, weight: .bold)); Text("78'").foregroundStyle(AppTheme.green).bold() }
                Spacer()
                team("الهلال", icon: "moon.stars.fill")
            }
            Divider().overlay(Color.white.opacity(0.1))
            VStack(spacing: 12) {
                stat("الاستحواذ", left: 58, right: 42)
                stat("التسديدات", left: 14, right: 8)
                stat("التسديدات على المرمى", left: 6, right: 3)
            }
        }.padding(18).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20)).padding(.horizontal, 16)
    }
    private func team(_ name: String, icon: String) -> some View { VStack(spacing: 8) { Image(systemName: icon).font(.system(size: 40)).foregroundStyle(AppTheme.green); Text(name).bold() } }
    private func stat(_ title: String, left: Int, right: Int) -> some View {
        VStack(spacing: 5) {
            HStack { Text("\(left)%").font(.caption); Spacer(); Text(title).font(.caption).foregroundStyle(AppTheme.muted); Spacer(); Text("\(right)%").font(.caption) }
            ProgressView(value: Double(left), total: Double(max(left + right, 1))).tint(AppTheme.green)
        }
    }
    private func matchRow(_ m: MatchItem) -> some View {
        HStack { Text(m.home).bold(); Spacer(); Text(m.minute).foregroundStyle(AppTheme.muted); Spacer(); Text(m.away).bold() }
            .padding(18).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 16)
    }
}

struct NewsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                TopBar(title: "الأخبار")
                ForEach(MockData.news) { item in
                    VStack(alignment: .leading, spacing: 10) {
                        RoundedRectangle(cornerRadius: 14).fill(AppTheme.soft).frame(height: 150).overlay(Image(systemName: item.image).font(.system(size: 48)).foregroundStyle(AppTheme.green))
                        Text(item.title).font(.headline)
                        Text(item.subtitle).font(.subheadline).foregroundStyle(AppTheme.muted)
                    }.padding(14).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
                }
            }.padding(.bottom, 24)
        }.background(AppTheme.bg.ignoresSafeArea())
    }
}

struct TransfersView: View {
    @State private var segment = "الكل"
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                TopBar(title: "مركز الانتقالات")
                SegmentBar(items: ["الكل", "رسمي", "موثوق", "شائعات"], selected: $segment)
                ForEach(MockData.transfers) { item in transferCard(item) }
            }.padding(.bottom, 24)
        }.background(AppTheme.bg.ignoresSafeArea())
    }
    private func transferCard(_ item: TransferItem) -> some View {
        HStack(spacing: 14) {
            Circle().fill(AppTheme.soft).frame(width: 74, height: 74).overlay(Image(systemName: "person.crop.circle.fill").font(.system(size: 50)).foregroundStyle(AppTheme.green))
            VStack(alignment: .leading, spacing: 6) {
                Text(item.probability >= 65 ? "90+ VERIFY" : "مصدر موثوق").font(.caption2.bold()).foregroundStyle(item.probability >= 65 ? .black : .white).padding(.horizontal, 8).padding(.vertical, 4).background(item.probability >= 65 ? AppTheme.green : AppTheme.soft, in: Capsule())
                Text(item.player).font(.headline)
                Text("\(item.from)  ←  \(item.to)").font(.caption).foregroundStyle(AppTheme.muted)
                Text(item.status).font(.caption2).foregroundStyle(AppTheme.green)
                ProgressView(value: Double(item.probability), total: 100).tint(AppTheme.green)
            }
            Text("\(item.probability)%").font(.headline)
        }.padding(14).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
    }
}

struct ProfileView: View {
    var body: some View {
        VStack(spacing: 18) {
            TopBar(title: "حسابي")
            Spacer()
            Image(systemName: "person.crop.circle.fill").font(.system(size: 84)).foregroundStyle(AppTheme.green)
            Text("مرحباً بك في 90+").font(.title2.bold())
            Text("الإشعارات • المفضلة • الفرق التي تتابعها • الإعدادات").foregroundStyle(AppTheme.muted).multilineTextAlignment(.center).padding(.horizontal)
            Spacer()
        }.background(AppTheme.bg.ignoresSafeArea())
    }
}
