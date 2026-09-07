import SwiftUI
import Foundation

enum AppTheme {
    static let green = Color(red: 0.06, green: 0.92, blue: 0.49)
    static let greenDeep = Color(red: 0.01, green: 0.38, blue: 0.22)
    static let bg = Color(red: 0.006, green: 0.024, blue: 0.031)
    static let card = Color(red: 0.018, green: 0.060, blue: 0.071)
    static let cardRaised = Color(red: 0.027, green: 0.087, blue: 0.100)
    static let soft = Color.white.opacity(0.065)
    static let border = Color.white.opacity(0.08)
    static let muted = Color.white.opacity(0.64)
    static let dimmed = Color.white.opacity(0.40)
}

enum SportsArabic {
    private static let leagueMap: [String: String] = [
        "Saudi Pro League": "دوري روشن السعودي",
        "Pro League": "دوري روشن السعودي",
        "Saudi League": "دوري روشن السعودي",
        "King's Cup": "كأس خادم الحرمين الشريفين",
        "Super Cup": "كأس السوبر السعودي",
        "AFC Champions League Elite": "دوري أبطال آسيا للنخبة",
        "AFC Champions League": "دوري أبطال آسيا",
        "AFC Champions League Two": "دوري أبطال آسيا 2",
        "Premier League": "الدوري الإنجليزي الممتاز",
        "La Liga": "الدوري الإسباني",
        "Bundesliga": "الدوري الألماني",
        "Serie A": "الدوري الإيطالي",
        "Ligue 1": "الدوري الفرنسي",
        "UEFA Champions League": "دوري أبطال أوروبا",
        "UEFA Europa League": "الدوري الأوروبي",
        "UEFA Europa Conference League": "دوري المؤتمر الأوروبي",
        "UEFA Nations League": "دوري الأمم الأوروبية",
        "FIFA Club World Cup": "كأس العالم للأندية",
        "World Cup": "كأس العالم",
        "Friendlies": "مباريات ودية"
    ]

    private static let teamMap: [String: String] = [
        "Al-Hilal Saudi FC": "الهلال", "Al Hilal": "الهلال", "Al-Hilal": "الهلال",
        "Al-Nassr": "النصر", "Al Nassr": "النصر", "Al-Nassr FC": "النصر",
        "Al-Ittihad FC": "الاتحاد", "Al Ittihad": "الاتحاد", "Al-Ittihad": "الاتحاد",
        "Al-Ahli Jeddah": "الأهلي", "Al Ahli": "الأهلي", "Al-Ahli Saudi FC": "الأهلي",
        "Al-Qadisiyah FC": "القادسية", "Al-Qadisiyah": "القادسية", "Al Qadsiah": "القادسية",
        "Al-Ettifaq": "الاتفاق", "Al Ettifaq": "الاتفاق",
        "Al-Shabab": "الشباب", "Al Shabab": "الشباب",
        "Al-Taawoun": "التعاون", "Al Taawon": "التعاون",
        "Al-Fateh": "الفتح", "Al Fateh": "الفتح",
        "Al-Fayha": "الفيحاء", "Al Feiha": "الفيحاء",
        "Al-Khaleej Saihat": "الخليج", "Al Khaleej": "الخليج",
        "Al-Raed": "الرائد", "Al Raed": "الرائد",
        "Damac": "ضمك", "Damac FC": "ضمك",
        "Al Riyadh": "الرياض", "Al-Riyadh": "الرياض",
        "Al-Okhdood": "الأخدود", "Al Akhdoud": "الأخدود",
        "Al-Kholood": "الخلود", "Al Kholood": "الخلود",
        "NEOM": "نيوم", "Neom SC": "نيوم",
        "Real Madrid": "ريال مدريد", "FC Barcelona": "برشلونة", "Barcelona": "برشلونة",
        "Atletico Madrid": "أتلتيكو مدريد", "Athletic Club": "أتلتيك بلباو",
        "Manchester City": "مانشستر سيتي", "Manchester United": "مانشستر يونايتد",
        "Liverpool": "ليفربول", "Arsenal": "أرسنال", "Chelsea": "تشيلسي",
        "Tottenham": "توتنهام", "Newcastle": "نيوكاسل", "Aston Villa": "أستون فيلا",
        "Bayern Munich": "بايرن ميونخ", "Borussia Dortmund": "بوروسيا دورتموند",
        "Paris Saint Germain": "باريس سان جيرمان", "Paris Saint-Germain": "باريس سان جيرمان",
        "Inter": "إنتر", "Inter Milan": "إنتر", "AC Milan": "ميلان", "Juventus": "يوفنتوس",
        "Napoli": "نابولي", "AS Roma": "روما", "Benfica": "بنفيكا", "FC Porto": "بورتو"
    ]

    static func league(_ value: String) -> String {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return leagueMap[key] ?? key
    }

    static func team(_ value: String) -> String {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return teamMap[key] ?? key
    }

    static func country(_ value: String?) -> String? {
        guard let value else { return nil }
        let map: [String: String] = [
            "Saudi-Arabia": "السعودية", "Saudi Arabia": "السعودية", "England": "إنجلترا",
            "Spain": "إسبانيا", "Germany": "ألمانيا", "Italy": "إيطاليا", "France": "فرنسا",
            "Portugal": "البرتغال", "Brazil": "البرازيل", "Argentina": "الأرجنتين",
            "Netherlands": "هولندا", "Belgium": "بلجيكا", "Turkey": "تركيا", "Morocco": "المغرب",
            "Egypt": "مصر", "Algeria": "الجزائر", "Tunisia": "تونس", "Senegal": "السنغال",
            "Croatia": "كرواتيا", "Serbia": "صربيا", "Uruguay": "الأوروغواي", "Colombia": "كولومبيا"
        ]
        return map[value] ?? value
    }

    static func eventType(_ value: String?) -> String {
        switch value?.lowercased() {
        case "goal": return "هدف"
        case "card": return "بطاقة"
        case "subst": return "تبديل"
        case "var": return "تقنية الفيديو"
        default: return value ?? "حدث"
        }
    }

    static func position(_ value: String?) -> String? {
        guard let value else { return nil }
        let map = ["Goalkeeper": "حارس مرمى", "Defender": "مدافع", "Midfielder": "وسط", "Attacker": "مهاجم"]
        return map[value] ?? value
    }
}

struct BrandLogo: View {
    var compact = false

    var body: some View {
        HStack(spacing: 0) {
            Text("90")
                .font(.system(size: compact ? 30 : 40, weight: .black, design: .rounded))
                .tracking(-2.2)
            Text("+")
                .font(.system(size: compact ? 25 : 34, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.green)
                .offset(y: -3)
        }
        .accessibilityLabel("90+")
    }
}

struct TopBar: View {
    let title: String?
    var showsLogo = false
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if showsLogo {
                BrandLogo()
            } else if let title {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 27, weight: .bold, design: .rounded))
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
        .padding(.top, 9)
        .padding(.bottom, 3)
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
