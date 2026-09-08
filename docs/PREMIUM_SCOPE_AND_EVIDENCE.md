# 90+ Premium Pulse — implementation and limits

## Scope

This is an implementation of a subset of the 20 ideas plus Pulse and Brief
approved in this conversation. It is not a 200-feature completion claim, nor a
claim that every proposed Premium idea is complete. It builds on PR29 and
includes the previously staged comparison same-ID and route identity fixes.
Production main and the backend are unchanged. Existing dark/green styling,
Gregorian Riyadh dates, Latin digits and source/provider rules are retained.

## Implemented product paths

| Experience | Shipped path in this development branch | Boundaries |
|---|---|---|
| Pulse / Match-day center | Home → 90+ Pulse; More → 2.0 → Pulse | Ranks received fixtures by exact follow IDs, phase and kickoff; not an event streaming service |
| 90+ Brief | Pulse → وش فاتني؟ | Persistent observed-score/status changes and explicit read marker; first visit is never labelled as missed activity |
| Personal daily brief / Smart favorites | Pulse → يومي; personal filter; current shared favorite team/league/match IDs | No claim of personal player-news entity linking |
| What did I miss? | Match → premium experience | Previously viewed event signatures vs current published events; first visit has a separate summary |
| Live 360 / Story | Match → premium experience tabs | Actual event timeline, event-count distribution and published statistics; never label event density as offensive momentum |
| Match Intelligence / Team DNA | Match experience → team comparison; team profile → DNA | W/D/L, scored/conceded, clean sheets and home/away filters from the available recent fixture window |
| Form Index | Team DNA / comparison | (3×wins + draws)/(3×sample size)×100; at least 3 valid games; no win probability or opponent adjustment |
| H2H Lab | Team comparison | Only encounters in received samples, not complete historical H2H; absent sample is explicitly labelled |
| Saved news / source filters | Pulse or Power Center → reading room | Titles, source, link and dates are saved; full articles are not copied or available offline |
| Transfer reading | Reading room → transfers | Search/source filters and source links; reports are not silently promoted to official confirmations or made-up reliability percentages |
| Interactive lineup | Existing saved lineup tool | Drag/swap, accessible swap menu, captain, up to 9 substitutes, persistent validated draft, text and generated-image share |
| Offline subsets | Pulse snapshots, change history, seen-event history, saved article metadata and recent team-analysis cache | Not a full offline season/player/standings database; receipt time is visible and is not provider event time |
| Live Activity fixes | Canonical refresh path and score masking | Foreground updates only; requires app receipt of data and normal iOS permission |

## Not complete / not enabled

- Genuine background match notification delivery and background Live Activity
  updates require signed APNs entitlements, tokens and a configured server-side
  delivery service. No new paid provider or signing setup was activated.
- Player Radar form history and percentiles need a consistent player/match and
  comparison-population dataset. Existing season-aware comparison is retained;
  do not call its profile metrics a complete percentile scouting system.
- Spatial tracking/shot/heat/passing maps and a genuine momentum model need the
  relevant licensed/source data and validation. They are not generated from a
  sparse goals/cards feed.
- Comprehensive transfer entity timelines/reliability assessment, broader league
  assist/round datasets, full offline statistics and global cross-content search
  remain separate work. Existing normal search and league hubs remain intact.
- No claim of physical-device verification, push delivery, paid entitlements,
  App Store/TestFlight publication, or complete end-to-end provider coverage.

## Truth and safety

Scores decreasing are recorded as a changed score, never a new goal. Nil scores
remain unknown. Conflicting duplicate IDs do not create a fabricated event.
Different providers' numeric namespaces are not matched by name. Shootout
results are excluded from W/D/L form metrics because regular scores alone do
not identify their winner. Source values may be cached; receipt-time metadata
is always labelled as receipt, not as an actual event timestamp.

Corrupt/oversized/unknown-version local archives are not overwritten silently.
All caches and libraries have limits. New optional lineup fields preserve the
old saved-library JSON representation on decode. No authentication secrets are
stored in these archives.

## Evidence

Local Linux Swift 6.2.1, Swift 5 mode: the actual new Foundation domain source
passed 122 assertions. This covers ranking, namespaced follow IDs, score/status
changes, first-visit handling, read markers, event classification, deduplication,
form math, sample constraints, cache limits, serialization, corrupt input, safe
article URL schemes and lineup swap bounds.

CI workflow: `.github/workflows/premium-pulse.yml`. It must pass on this branch's
head before calling the preview build verified. It runs existing recovery and
comparison tests, the entire release transform pipeline, guarded/idempotent
integration checks, lineup migration checks, iPhone Release compilation and
actual limited iPhone-simulator UI smoke tests. Test screenshots are retained
inside the xcresult artifact; merely creating screenshots is not manual visual
inspection. CI results and commit IDs belong in the PR, not invented here.
