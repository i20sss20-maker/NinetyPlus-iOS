"""Execute the actual search store with controllable providers, without UI/network."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/Views/PremiumGlobalSearch.swift').read_text(encoding='utf-8')
store = source.split('@MainActor final class PremiumGlobalSearchStore', 1)[1].split('struct PremiumGlobalSearch: View', 1)[0]
mock = r'''
import Foundation
import Combine
struct APIPlusTeam { let name: String }
struct APIPlusPlayer { let name: String }
@MainActor final class APISportsStore {
    static let shared = APISportsStore()
    var teams: [String: CheckedContinuation<[APIPlusTeam], Error>] = [:]
    var players: [String: CheckedContinuation<[APIPlusPlayer], Error>] = [:]
    func searchTeams(_ text: String) async throws -> [APIPlusTeam] {
        try await withCheckedThrowingContinuation { teams[text] = $0 }
    }
    func searchPlayers(_ text: String) async throws -> [APIPlusPlayer] {
        try await withCheckedThrowingContinuation { players[text] = $0 }
    }
    func finish(_ text: String) {
        teams.removeValue(forKey: text)!.resume(returning: [APIPlusTeam(name: text)])
        players.removeValue(forKey: text)!.resume(returning: [APIPlusPlayer(name: text)])
    }
}
'''
test = r'''
@main struct SearchTests {
    @MainActor static func pending(_ query: String) async throws {
        for _ in 0..<500 {
            if APISportsStore.shared.teams[query] != nil && APISportsStore.shared.players[query] != nil { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        fatalError("Provider request did not start")
    }
    @MainActor static func main() async throws {
        let store = PremiumGlobalSearchStore()
        let first = Task { await store.search("Old") }
        try await pending("Old")
        APISportsStore.shared.finish("Old"); await first.value
        precondition(store.teams.value?.first?.name == "Old")
        let second = Task { await store.search("Next") }
        try await Task.sleep(for: .milliseconds(30))
        precondition(store.teams.value == nil && store.players.value == nil, "Clear old results before debounce")
        precondition(store.teams.isLoading && store.players.isLoading)
        try await pending("Next")
        let third = Task { await store.search("Newest") }
        try await Task.sleep(for: .milliseconds(30))
        APISportsStore.shared.finish("Next"); await second.value
        precondition(store.teams.value == nil && store.players.value == nil, "Late old response must be ignored")
        precondition(store.teams.isLoading && store.players.isLoading, "Old defer must not stop newer spinner")
        try await pending("Newest")
        await store.search(" ")
        APISportsStore.shared.finish("Newest"); await third.value
        precondition(store.teams.value == nil && store.players.value == nil, "Clearing query must invalidate in-flight results")
        precondition(!store.teams.isLoading && !store.players.isLoading)
        let cancelled = Task { await store.search("Cancel") }
        try await Task.sleep(for: .milliseconds(30)); cancelled.cancel(); await cancelled.value
        precondition(!store.teams.isLoading && !store.players.isLoading, "Cancelled debounce must clean loading state")
        print("Global search: debounce, stale responses, clear and cancellation passed")
    }
}
'''
with tempfile.TemporaryDirectory() as tmp:
    swift = Path(tmp) / 'SearchTests.swift'
    swift.write_text(mock + '@MainActor final class PremiumGlobalSearchStore' + store + test, encoding='utf-8')
    binary = Path(tmp) / 'search-tests'
    subprocess.run(['swiftc', '-swift-version', '5', '-parse-as-library',
                    str(root / 'Sources/Core/PageResource.swift'), str(swift), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
