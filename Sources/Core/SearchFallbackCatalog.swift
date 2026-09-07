import Foundation

/// Small identity catalog used only when a live search provider is unavailable or
/// omits a well-known entity. It contains stable identity/profile data, never
/// dynamic scores, fixtures or season statistics.
enum SearchFallbackCatalog {
    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ar"))
            .replacingOccurrences(of: "أ", with: "ا")
            .replacingOccurrences(of: "إ", with: "ا")
            .replacingOccurrences(of: "آ", with: "ا")
            .replacingOccurrences(of: "ى", with: "ي")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func teams(query: String) -> [APIPlusTeam] {
        let q = normalized(query)
        guard !q.isEmpty else { return [] }
        let records: [(aliases: [String], team: APIPlusTeam)] = [
            (["الاتحاد", "اتحاد جدة", "ittihad", "al ittihad", "al-ittihad"],
             APIPlusTeam(id: "2938", name: "Al-Ittihad FC", country: "Saudi-Arabia", founded: 1927,
                         logo: "https://media.api-sports.io/football/teams/2938.png", venue: nil, city: "Jeddah", venueImage: nil))
        ]
        return records.compactMap { entry in
            entry.aliases.contains(where: { normalized($0).contains(q) || q.contains(normalized($0)) }) ? entry.team : nil
        }
    }

    static func players(query: String) -> [APIPlusPlayer] {
        let q = normalized(query)
        guard !q.isEmpty else { return [] }
        let records: [(aliases: [String], player: APIPlusPlayer)] = [
            (["رونالدو", "كريستيانو", "كريستيانو رونالدو", "ronaldo", "cristiano", "cristiano ronaldo"],
             APIPlusPlayer(id: "874", name: "Cristiano Ronaldo", nationality: "Portugal", birth: "1985-02-05",
                           height: "187 cm", weight: "83 kg", photo: "https://media.api-sports.io/football/players/874.png"))
        ]
        return records.compactMap { entry in
            entry.aliases.contains(where: { normalized($0).contains(q) || q.contains(normalized($0)) }) ? entry.player : nil
        }
    }

    static func mergeTeams(_ live: [APIPlusTeam], query: String) -> [APIPlusTeam] {
        merge(live, fallback: teams(query: query))
    }

    static func mergePlayers(_ live: [APIPlusPlayer], query: String) -> [APIPlusPlayer] {
        merge(live, fallback: players(query: query))
    }

    private static func merge<T: Identifiable>(_ live: [T], fallback: [T]) -> [T] where T.ID: Hashable {
        var seen = Set<T.ID>()
        return (fallback + live).filter { seen.insert($0.id).inserted }
    }
}
