# 90+ 2.0 — all-at-once product contract

Build 105 remains the rollback baseline. This branch is the integrated 2.0 development line.

## Non-negotiable product rules
- Arabic UI uses English digits 0–9 everywhere.
- Never invent stats, injuries, xG, odds, contracts, or broadcast rights.
- Partial data never blocks an otherwise usable page.
- One canonical match center is the destination for all match cards.
- Follow/favorite state is shared across Home, Matches, Club, Player and League hubs.
- Server-side fallbacks remain authoritative for source selection and quota degradation.
- Advanced modules are visible only when backed by real source data or supported platform capability.

## Integrated scope
Home personalization, My Team, Saudi Hub, matches filters, calendar, spoiler mode, league/team/player hubs, pre/post-match insights, lineup state, injuries/availability when sourced, H2H/form, momentum/shot/heat/passing/defensive maps when sourced, player/team comparison, lineup builder, sharing cards, saved news, source filters, notifications preferences, Live Activities, widgets, deep links, calendar export, offline/stale cache, low-data mode, smart prefetch, analytics/performance hooks, feature flags, source-health monitoring.

This file is intentionally product-facing: implementation must remain source-truthful and degrade gracefully when a provider does not expose a requested metric.
