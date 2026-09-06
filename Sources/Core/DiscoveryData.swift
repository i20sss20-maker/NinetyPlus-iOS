import Foundation

struct PlayerProfile: Identifiable, Decodable, Hashable {
    var id: String { idPlayer ?? UUID().uuidString }
    let idPlayer: String?
    let strPlayer: String?
    let strTeam: String?
    let strSport: String?
    let strNationality: String?
    let dateBorn: String?
    let strPosition: String?
    let strNumber: String?
    let strHeight: String?
    let strWeight: String?
    let strThumb: String?
    let strCutout: String?
    let strBanner: String?
    let strDescriptionEN: String?
}

private struct SearchTeamResponse: Decodable { let teams: [TeamProfile]? }
private struct SearchPlayerResponse: Decodable { let player: [PlayerProfile]? }

extension FootballAPI {
    static func searchTeams(_ query: String) async throws -> [TeamProfile] {
        guard let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        let url = URL(string: "\(base)/searchteams.php?t=\(q)")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("NinetyPlus/1.0 iOS", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(SearchTeamResponse.self, from: data).teams ?? []
    }

    static func searchPlayers(_ query: String) async throws -> [PlayerProfile] {
        guard let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        let url = URL(string: "\(base)/searchplayers.php?p=\(q)")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("NinetyPlus/1.0 iOS", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(SearchPlayerResponse.self, from: data).player ?? []
    }
}
