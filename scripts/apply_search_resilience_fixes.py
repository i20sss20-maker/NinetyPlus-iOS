"""Make discover search survive provider quota exhaustion without inventing dynamic data."""
from pathlib import Path

p = Path("Sources/Views/V2Discovery.swift")
s = p.read_text()

old_teams = '''        do {\n            let values = try await APISportsStore.shared.searchTeams(providerText(text))\n            try Task.checkCancellation()\n            if entered == text { teams.succeed(values, token: token) }\n        } catch {\n            if !Task.isCancelled && !(error is CancellationError) && entered == text { teams.fail(error.localizedDescription, token: token) }\n        }'''
new_teams = '''        do {\n            let live = try await APISportsStore.shared.searchTeams(providerText(text))\n            try Task.checkCancellation()\n            let values = SearchFallbackCatalog.mergeTeams(live, query: text)\n            if entered == text { teams.succeed(values, token: token) }\n        } catch {\n            guard !Task.isCancelled, !(error is CancellationError), entered == text else { return }\n            let fallback = SearchFallbackCatalog.teams(query: text)\n            if fallback.isEmpty { teams.fail(error.localizedDescription, token: token) }\n            else { teams.succeed(fallback, token: token) }\n        }'''
old_players = '''        do {\n            let values = try await APISportsStore.shared.searchPlayers(providerText(text))\n            try Task.checkCancellation()\n            if entered == text { players.succeed(values, token: token) }\n        } catch {\n            if !Task.isCancelled && !(error is CancellationError) && entered == text { players.fail(error.localizedDescription, token: token) }\n        }'''
new_players = '''        do {\n            let live = try await APISportsStore.shared.searchPlayers(providerText(text))\n            try Task.checkCancellation()\n            let values = SearchFallbackCatalog.mergePlayers(live, query: text)\n            if entered == text { players.succeed(values, token: token) }\n        } catch {\n            guard !Task.isCancelled, !(error is CancellationError), entered == text else { return }\n            let fallback = SearchFallbackCatalog.players(query: text)\n            if fallback.isEmpty { players.fail(error.localizedDescription, token: token) }\n            else { players.succeed(fallback, token: token) }\n        }'''

for old, new, label in [(old_teams, new_teams, "team search"), (old_players, new_players, "player search")]:
    if new in s:
        continue
    if old not in s:
        raise SystemExit(f"search resilience patch missing: {label}")
    s = s.replace(old, new, 1)

p.write_text(s)
print("Applied resilient discover search fallbacks")
