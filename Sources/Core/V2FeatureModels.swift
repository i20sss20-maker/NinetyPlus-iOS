import Foundation

/// A route never sends an external provider's namespaced ID to API-Football.
struct V2ContentRoute: Hashable, Identifiable {
    enum Kind: String { case match, team, player, league }
    let kind: Kind
    let identifier: String
    let kickoff: Date?
    var id: String { "\(kind.rawValue)|\(identifier)|\(kickoff?.timeIntervalSince1970 ?? 0)" }

    init?(kind: Kind, identifier: String, kickoff: Date? = nil) {
        guard identifier.count <= 240, !identifier.isEmpty else { return nil }
        let isNumber = identifier.utf8.allSatisfy { (48...57).contains($0) }
        if isNumber {
            guard let number = UInt64(identifier), number > 0 else { return nil }
            self.identifier = String(number)
        } else {
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:-_.")
            guard kind == .match, identifier.hasPrefix("np:"), identifier.count > 3,
                  identifier.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
            self.identifier = identifier
        }
        if let kickoff {
            guard kind == .match, kickoff.timeIntervalSince1970.isFinite,
                  (0...4_102_444_800).contains(kickoff.timeIntervalSince1970) else { return nil }
        }
        self.kind = kind
        self.kickoff = kickoff
    }

    init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "ninetyplus", parts.user == nil,
              parts.password == nil, parts.port == nil, parts.fragment == nil,
              let host = parts.host?.lowercased(), let kind = Kind(rawValue: host),
              parts.percentEncodedPath.hasPrefix("/") else { return nil }
        let encoded = String(parts.percentEncodedPath.dropFirst())
        guard !encoded.contains("/"), let identifier = encoded.removingPercentEncoding else { return nil }
        let items = parts.queryItems ?? []
        guard items.count <= 1, items.allSatisfy({ $0.name == "kickoff" }) else { return nil }
        var kickoff: Date?
        if let item = items.first {
            guard let value = item.value, let seconds = Double(value), seconds.isFinite else { return nil }
            kickoff = Date(timeIntervalSince1970: seconds)
        }
        self.init(kind: kind, identifier: identifier, kickoff: kickoff)
    }

    var url: URL? {
        var parts = URLComponents()
        parts.scheme = "ninetyplus"
        parts.host = kind.rawValue
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        guard let path = identifier.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        parts.percentEncodedPath = "/" + path
        if let kickoff { parts.queryItems = [.init(name: "kickoff", value: String(kickoff.timeIntervalSince1970))] }
        return parts.url
    }
}

struct V2LineupDraft: Codable, Equatable, Identifiable {
    static let formations = ["4-3-3", "4-2-3-1", "4-4-2", "3-5-2", "3-4-3"]
    var id = UUID()
    var title = "تشكيلتي"
    var formation = "4-3-3"
    var names = Array(repeating: "", count: 11)
    var updatedAt = Date()

    var isValid: Bool {
        Self.formations.contains(formation) && names.count == 11 && title.count <= 60 &&
        names.allSatisfy { $0.count <= 80 } && updatedAt.timeIntervalSince1970.isFinite
    }
    var filledCount: Int { names.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count }
    var rows: [[Int]] {
        var next = 0
        return ([1] + formation.split(separator: "-").compactMap { Int($0) }).map { count in
            defer { next += count }
            return Array(next..<(next + count))
        }
    }
    var shareText: String {
        let players = names.enumerated().map { index, value in
            let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(index + 1). \(name.isEmpty ? "—" : name)"
        }.joined(separator: "\n")
        return "90+ | \(title) | \(formation)\nتشكيلة من إعداد المستخدم، وليست تشكيلة رسمية.\n\(players)"
    }
}

struct V2LineupLibrary: Codable, Equatable {
    static let limit = 20
    private(set) var version = 1
    private(set) var drafts: [V2LineupDraft] = []
    private(set) var selectedID: UUID?

    enum StorageError: Error { case invalidData, full }
    var selected: V2LineupDraft? { drafts.first { $0.id == selectedID } }
    var isValid: Bool {
        version == 1 && drafts.count <= Self.limit && drafts.allSatisfy(\.isValid) &&
        Set(drafts.map(\.id)).count == drafts.count &&
        (selectedID == nil || drafts.contains { $0.id == selectedID })
    }
    static func decode(_ raw: String) throws -> Self {
        guard !raw.isEmpty else { return Self() }
        guard raw.utf8.count <= 256_000, let data = raw.data(using: .utf8) else { throw StorageError.invalidData }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.isValid else { throw StorageError.invalidData }
        return value
    }
    func encoded() throws -> String {
        guard isValid else { throw StorageError.invalidData }
        let data = try JSONEncoder().encode(self)
        guard let result = String(data: data, encoding: .utf8) else { throw StorageError.invalidData }
        return result
    }
    mutating func save(_ draft: V2LineupDraft) throws {
        guard draft.isValid else { throw StorageError.invalidData }
        if let index = drafts.firstIndex(where: { $0.id == draft.id }) { drafts[index] = draft }
        else {
            guard drafts.count < Self.limit else { throw StorageError.full }
            drafts.append(draft)
        }
        selectedID = draft.id
    }
    mutating func select(_ id: UUID) {
        guard drafts.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }
    mutating func remove(_ id: UUID) {
        drafts.removeAll { $0.id == id }
        if selectedID == id { selectedID = drafts.first?.id }
    }
}

enum V2ComparisonMath {
    static func per90(count: Int?, minutes: Int?) -> Double? {
        guard let count, let minutes, count >= 0, minutes > 0 else { return nil }
        let result = Double(count) * 90 / Double(minutes)
        return result.isFinite ? result : nil
    }
    static func display(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
    static func display(_ value: Int?) -> String {
        guard let value, value >= 0 else { return "—" }
        return String(value)
    }
}
