import Foundation

@MainActor
extension EditorialStore {
    func refreshIfStale(maxAge: TimeInterval = 90) async {
        if news.isEmpty || transfers.isEmpty {
            await refresh()
            return
        }

        guard let lastUpdated else {
            await refresh()
            return
        }

        if Date().timeIntervalSince(lastUpdated) >= maxAge {
            await refresh()
        }
    }
}
