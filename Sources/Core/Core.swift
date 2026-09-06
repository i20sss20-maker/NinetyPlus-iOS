import SwiftUI
import Foundation

struct NewsItem: Identifiable, Hashable {
    let id = UUID(); let title: String; let subtitle: String; let image: String; let tag: String
}
struct MatchItem: Identifiable, Hashable {
    let id = UUID(); let home: String; let away: String; let homeScore: Int?; let awayScore: Int?; let minute: String
}
struct TransferItem: Identifiable, Hashable {
    let id = UUID(); let player: String; let from: String; let to: String; let status: String; let probability: Int
}

enum MockData {
    static let news: [NewsItem] = [
        .init(title: "النجم يعود بقوة", subtitle: "بعد فترة غياب طويلة.. جاهز لقيادة فريقه في المواجهة القادمة", image: "soccerball", tag: "حصري"),
        .init(title: "مدرب الفريق: نثق في قدرتنا على تحقيق اللقب", subtitle: "منذ 3 ساعات", image: "sportscourt", tag: "خبر"),
        .init(title: "ملعب المدينة يستعد لاستضافة القمة المنتظرة", subtitle: "منذ 5 ساعات", image: "building.columns", tag: "خبر"),
        .init(title: "موهبة شابة تخطف الأنظار في الدوري المحلي", subtitle: "منذ 6 ساعات", image: "figure.soccer", tag: "تقرير")
    ]
    static let matches: [MatchItem] = [
        .init(home: "النسر", away: "الهلال", homeScore: 2, awayScore: 1, minute: "78'"),
        .init(home: "الوحدة", away: "الريان", homeScore: nil, awayScore: nil, minute: "10:00 مساءً"),
        .init(home: "الاتحاد", away: "القادسية", homeScore: nil, awayScore: nil, minute: "غداً")
    ]
    static let transfers: [TransferItem] = [
        .init(player: "علي الحربي", from: "نادي العاصمة", to: "النخبة", status: "صفقة رسمية", probability: 100),
        .init(player: "ماركو فييرا", from: "نادي القوة", to: "الاتحاد", status: "مفاوضات متقدمة", probability: 80),
        .init(player: "سالم العنزي", from: "نادي النخبة", to: "الهلال", status: "اهتمام جاد", probability: 65),
        .init(player: "إسماعيل كوني", from: "نادي الشرق", to: "النصر", status: "مفاوضات أولية", probability: 40),
        .init(player: "لوكا مارتينيز", from: "نادي القمة", to: "الهلال", status: "شائعة", probability: 20)
    ]
}

enum AppTheme {
    static let green = Color(red: 0.04, green: 0.92, blue: 0.48)
    static let bg = Color(red: 0.015, green: 0.055, blue: 0.065)
    static let card = Color(red: 0.025, green: 0.10, blue: 0.115)
    static let soft = Color.white.opacity(0.07)
    static let muted = Color.white.opacity(0.58)
}

struct BrandLogo: View {
    var body: some View {
        HStack(spacing: 2) {
            Text("90").font(.system(size: 42, weight: .black, design: .rounded)).italic()
            Text("+").font(.system(size: 36, weight: .black, design: .rounded)).foregroundStyle(AppTheme.green).offset(y: -2)
        }.accessibilityLabel("90+")
    }
}

struct TopBar: View {
    let title: String?; var showsLogo = false
    var body: some View {
        HStack {
            Button(action: {}) { Image(systemName: "magnifyingglass").font(.title3) }
            Spacer()
            if showsLogo { BrandLogo() } else if let title { Text(title).font(.title2.bold()) }
            Spacer()
            Button(action: {}) { Image(systemName: "bell").font(.title3) }
        }.foregroundStyle(.white).padding(.horizontal, 18).padding(.top, 6)
    }
}

struct SegmentBar: View {
    let items: [String]; @Binding var selected: String
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Button(item) { selected = item }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected == item ? .black : .white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(selected == item ? AppTheme.green : AppTheme.soft, in: RoundedRectangle(cornerRadius: 10))
                }
            }.padding(.horizontal, 16)
        }
    }
}

final class APIClient {
    static let shared = APIClient(); private init() {}
    var baseURL = URL(string: "https://api.example.com")!
    func request<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let url = baseURL.appending(path: path)
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
