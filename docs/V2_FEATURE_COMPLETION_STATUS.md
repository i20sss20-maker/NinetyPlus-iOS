# 90+ V2 implementation status — 2026-09-08

## Scope and provenance

The user requested all of the previously discussed 200 items. The recoverable
repository contract is `docs/V2_0_ALL_AT_ONCE_PLAN.md`, a grouped scope, not a
numbered 200-item acceptance checklist. Conversation/library retrieval did not
recover that original numbered list. This file does NOT replace it with an
invented list, claim a completion percentage, or certify 200 features complete.

This branch is based on PR #28 (`b11fcacb783cff0cd16d90f91aeb8dc51be5444d`) and
includes its Match Center recovery fix without merging or changing production.
Only NinetyPlus-iOS is in scope; BLOFY projects and the backend are unchanged.

## Implemented in this batch

- Saved lineup library: automatic on-device persistence, up to 20 named drafts,
  five supported formations, a position preview, editing, switching, deletion
  with confirmation, validated restoration, and text sharing that explicitly
  labels the lineup as user-authored rather than an official team lineup.
- Player comparison: independent cancellable searches, selection/change/swap,
  independent loading/error/retry, published season/club/competition selection,
  appearances/minutes/goals/assists/cards/source rating, and derived per-90 goals
  and assists only when the published count and positive minutes are available.
  Missing values remain unknown; a fallback season is explicitly labelled.
- Content routes: validated and percent-encoded match/team/player/league links,
  optional match kickoff context, actual destination resolution with retry,
  cancellation and request-token ownership. Featured leagues are supported;
  unsupported league IDs display an unavailable state. External provider IDs
  are never sent to API-Football's numeric endpoints.
- Match sharing respects the score spoiler setting and includes kickoff context.
- Match Center Low Data Mode increases the refresh interval to at least 120s.
  This does not claim that every image download is now reduced or disabled.
- Superseded simple lineup/comparison implementations are removed from the
  generated release source. The existing theme is reused, not redesigned.

The feature integration runs at the end of `apply_v2_final_polish.py`, so the
standard IPA and visual workflows consume it too. Each source anchor is checked;
a missing or ambiguous anchor stops the build rather than silently omitting a
feature. The new integration is checked for idempotence on real generated Swift.

## Validation boundaries

Local: 52 Foundation-model assertions passed with Swift 6.2.1 in Swift 5 mode.
GitHub validation is recorded in the PR: full transform chain, regression suite,
iPhone release compilation and simulator/UI-test compilation. A compiled UI-test
bundle is not an executed UI test or a physical iPhone test. Any generated IPA
is unsigned, not TestFlight, and is not a signed distribution release.

## Still not certified complete

The original 200-item checklist must be recovered before claiming item-by-item
completion. In the documented grouped scope, this batch does not certify team
comparison, complete favorite-home preference wiring, saved-news/source filters,
all spoiler surfaces, disk-backed sports offline cache, smart prefetch, real
background push notification delivery, shared widget data, or every analytics,
performance and feature-flag hook. Provider-dependent injury/contract/broadcast
and spatial tracking modules must remain gated by actual licensed/source data;
labels, switches and placeholder screens are not completed features.
