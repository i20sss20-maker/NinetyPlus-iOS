import Foundation

struct LeagueOption: Identifiable, Hashable {
    let id: String
    let arabicName: String
    let englishName: String

    static let featured: [LeagueOption] = [
        .init(id: "4668", arabicName: "الدوري السعودي", englishName: "Saudi-Arabian Pro League"),
        .init(id: "4328", arabicName: "الدوري الإنجليزي", englishName: "English Premier League"),
        .init(id: "4335", arabicName: "الدوري الإسباني", englishName: "Spanish La Liga"),
        .init(id: "4331", arabicName: "الدوري الألماني", englishName: "German Bundesliga"),
        .init(id: "4332", arabicName: "الدوري الإيطالي", englishName: "Italian Serie A"),
        .init(id: "4334", arabicName: "الدوري الفرنسي", englishName: "French Ligue 1")
    ]
}
