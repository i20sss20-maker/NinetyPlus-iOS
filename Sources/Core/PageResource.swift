import Foundation

/// Value state used on the main actor by SwiftUI pages. Never turns a failed
/// refresh into an empty success, and rejects completions from older requests.
struct PageResource<Value> {
    private(set) var key: String?
    private(set) var value: Value?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastUpdated: Date?
    private var activeRequest: UUID?

    mutating func begin(key newKey: String, retainingValue: Bool = false) -> UUID {
        if key != newKey {
            if !retainingValue { value = nil }
            lastUpdated = nil
        }
        key = newKey
        errorMessage = nil
        isLoading = true
        let token = UUID()
        activeRequest = token
        return token
    }

    @discardableResult
    mutating func succeed(_ newValue: Value, token: UUID, warning: String? = nil, at date: Date = Date()) -> Bool {
        guard activeRequest == token else { return false }
        value = newValue
        errorMessage = warning
        lastUpdated = date
        isLoading = false
        activeRequest = nil
        return true
    }

    @discardableResult
    mutating func fail(_ message: String, token: UUID) -> Bool {
        guard activeRequest == token else { return false }
        errorMessage = message
        isLoading = false
        activeRequest = nil
        return true
    }

    mutating func cancel(token: UUID) {
        guard activeRequest == token else { return }
        activeRequest = nil
        isLoading = false
    }

    mutating func invalidate() {
        activeRequest = nil
        isLoading = false
    }

    func isFresh(key expectedKey: String, maxAge: TimeInterval, now: Date = Date()) -> Bool {
        guard key == expectedKey, value != nil, errorMessage == nil,
              let lastUpdated else { return false }
        let age = now.timeIntervalSince(lastUpdated)
        return age >= 0 && age < maxAge
    }
}

enum SavedFavoriteIDs {
    static func parse(_ raw: String) -> [String] {
        Array(Set(raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })).sorted()
    }
}

enum FixturePhase {
    static func isUpcoming(_ status: String) -> Bool {
        ["NS", "TBD"].contains(status.uppercased())
    }
    static func isFinished(_ status: String) -> Bool {
        ["FT", "AET", "PEN"].contains(status.uppercased())
    }
}
