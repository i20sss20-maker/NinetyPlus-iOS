import SwiftUI
import Foundation

enum AppTheme {
    static let green = Color(red: 0.06, green: 0.92, blue: 0.49)
    static let greenDeep = Color(red: 0.01, green: 0.38, blue: 0.22)
    static let bg = Color(red: 0.009, green: 0.035, blue: 0.043)
    static let card = Color(red: 0.022, green: 0.075, blue: 0.086)
    static let cardRaised = Color(red: 0.03, green: 0.095, blue: 0.108)
    static let soft = Color.white.opacity(0.065)
    static let border = Color.white.opacity(0.075)
    static let muted = Color.white.opacity(0.62)
    static let dimmed = Color.white.opacity(0.40)
}

enum SportsArabic {
    private static let leagueMap: [String: String] = [
        "Saudi Pro League": "دوري روشن السعودي",
        "Pro League": "دوري روشن السعودي",
        "King's Cup": "كأس خادم الحرمين الشريفين",
        "AFC Champions League Elite": "دوري أبطال آسيا للنخبة",
        "AFC Champions League": "دوري أبطال آسيا",
        "Premier League": "الدوري الإنجليزي الممتاز",
        "La Liga": "الدوري الإسباني",
        "Bundesliga": "الدوري الألماني",
        "Serie A": "الدوري الإيطالي",
        "Ligue 1": "الدوري الفرنسي",
        "UEFA Champions League": "دوري أبطال أوروبا",
        "UEFA Europa League": "الدوري الأوروبي"
    ]

    private static let teamMap: [String: String] = [
        "Al-Hilal Saudi FC": "الهلال",
        "Al Hilal": "الهلال",
        "Al-Nassr": "النصر",
        "Al Nassr": "النصر",
        "Al-Ittihad FC": "الاتحاد",
        "Al Ittihad": "الاتحاد",
        "Al-Ahli Jeddah": "الأهلي",
        "Al Ahli": "الأهلي",
        "Al-Qadisiyah FC": "القادسية",
        "Al-Qadisiyah": "القادسية",
        "Al-Ettifaq": "الاتفاق",
        "Al-Shabab": "الشباب",
        "Al-Taawoun": "التعاون",
        "Al-Fateh": "الفتح",
        "Al-Fayha": "الفيحاء",
        "Al-Khaleej Saihat": "الخليج",
        "Al-Raed": "الرائد",
        "Damac": "ضمك",
        "Al Riyadh": "الرياض",
        "Al-Okhdood": "الأخدود",
        "Al-Kholood": "الخلود",
        "NEOM": "نيوم",
        "Real Madrid": "ريال مدريد",
        "Barcelona": "برشلونة",
        "Manchester City": "مانشستر سيتي",
        "Manchester United": "مانشستر يونايتد",
        "Liverpool": "ليفربول",
        "Arsenal": "أرسنال",
        "Chelsea": "تشيلسي",
        "Bayern Munich": "بايرن ميونخ",
        "Paris Saint Germain": "باريس سان جيرمان",
        "Inter": "إنتر",
        "AC Milan": "ميلان",
        "Juventus": "يوفنتوس"
    ]

    static func league(_ value: String) -> String {
        leagueMap[value.trimmingCharacters(in: .whitespacesAndNewlines)] ?? value
    }

    static func team(_ value: String) -> String {
        teamMap[value.trimmingCharacters(in: .whitespacesAndNewlines)] ?? value
    }

    static func country(_ value: String?) -> String? {
        guard let value else { return nil }
        let map: [String: String] = [
            "Saudi-Arabia": "السعودية", "Saudi Arabia": "السعودية", "England": "إنجلترا",
            "Spain": "إسبانيا", "Germany": "ألمانيا", "Italy": "إيطاليا", "France": "فرنسا",
            "Portugal": "البرتغال", "Brazil": "البرازيل", "Argentina": "الأرجنتين"
        ]
        return map[value] ?? value
    }
}

struct BrandLogo: View {
    var compact = false

    var body: some View {
        HStack(spacing: 1) {
            Text("90")
                .font(.system(size: compact ? 30 : 39, weight: .black, design: .rounded))
                .tracking(-2)
            Text("+")
                .font(.system(size: compact ? 25 : 33, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.green)
                .offset(y: -2)
        }
        .accessibilityLabel("90+")
    }
}

/// Header without decorative buttons that do nothing. Navigation actions live where
/// they have a real destination in each screen.
struct TopBar: View {
    let title: String?
    var showsLogo = false
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if showsLogo {
                BrandLogo()
            } else if let title {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }
}

struct SegmentBar: View {
    let items: [String]
    @Binding var selected: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) { selected = item }
                    } label: {
                        Text(item)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selected == item ? .black : .white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(selected == item ? AppTheme.green : AppTheme.soft, in: Capsule())
                            .overlay(Capsule().stroke(selected == item ? Color.clear : AppTheme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
