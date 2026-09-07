import json
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

BASE = "https://ninetyplus-ios-production.up.railway.app"
OUT = Path("evidence/production-match-detail.json")
OUT.parent.mkdir(parents=True, exist_ok=True)
MAX_DETAIL_SECONDS = 6.0


def save(report):
    OUT.write_text(json.dumps(report, ensure_ascii=False, indent=2))


def fail(report, message):
    report["ok"] = False
    report["error"] = message
    save(report)
    raise SystemExit("production match probe: " + message)


def get_json(path, params=None, timeout=20):
    query = ("?" + urlencode(params)) if params else ""
    req = Request(BASE + path + query, headers={"User-Agent": "NinetyPlus-QA/1.6"})
    with urlopen(req, timeout=timeout) as response:
        return response.status, json.load(response)


def matches_from(payload):
    if isinstance(payload, dict):
        for key in ("matches", "fixtures", "response", "data"):
            value = payload.get(key)
            if isinstance(value, list): return value
    return payload if isinstance(payload, list) else []


def status_code(match):
    value = match.get("status") or match.get("state") or ""
    if isinstance(value, dict): return str(value.get("code") or value.get("text") or "").lower()
    return str(value).lower()


def is_finished(match):
    status = status_code(match)
    return any(token in status for token in ("ft", "finished", "full time", "aet", "pen"))


def team_name(match, side):
    value = match.get(side) or match.get(side + "Team")
    if isinstance(value, dict): return value.get("name") or value.get("displayName") or value.get("shortDisplayName")
    return value


def lineup_summary(lineup):
    team = lineup.get("team") or {}; coach = lineup.get("coach") or {}
    start = lineup.get("startXI") or lineup.get("startingXI") or []
    subs = lineup.get("substitutes") or lineup.get("bench") or []
    flat = lineup.get("players") or []
    if flat and not start and not subs:
        start = [p for p in flat if p.get("starter") is True]
        subs = [p for p in flat if p.get("starter") is not True]
    names = []
    for p in start + subs:
        player = p.get("player") if isinstance(p, dict) else None
        if isinstance(player, dict): names.append(player.get("name"))
        elif isinstance(p, dict): names.append(p.get("name"))
    return {"team": team.get("name") if isinstance(team, dict) else None,
            "teamId": team.get("id") if isinstance(team, dict) else None,
            "formation": lineup.get("formation"),
            "coach": coach.get("name") if isinstance(coach, dict) else None,
            "coachRaw": coach if isinstance(coach, dict) else None,
            "starters": len(start), "substitutes": len(subs),
            "namedPlayers": len([n for n in names if n])}


report = {"checkedAt": datetime.now(timezone.utc).isoformat(), "base": BASE, "days": []}
selected = None; selected_date = None
for offset in range(0, 8):
    day = (datetime.now(timezone.utc) - timedelta(days=offset)).date().isoformat()
    try:
        status, payload = get_json("/api/v2/fixtures", {"date": day})
        matches = matches_from(payload)
        report["days"].append({"date": day, "status": status, "count": len(matches),
                               "canonicalCount": (payload.get("meta") or {}).get("canonicalCount") if isinstance(payload, dict) else None})
        finished = next((m for m in matches if is_finished(m)), None)
        if finished is not None:
            selected = finished; selected_date = day; break
    except Exception as exc:
        report["days"].append({"date": day, "error": str(exc)})

if not selected: fail(report, "No completed fixture found in the last 8 days")
match_id = selected.get("canonicalId") or selected.get("id") or selected.get("matchID") or selected.get("matchId")
if not match_id or not str(match_id).startswith("np:"):
    report["selected"] = selected
    fail(report, "Selected fixture had no canonical id")

started = time.monotonic()
status, detail = get_json("/api/v2/match", {"id": str(match_id), "date": selected_date})
detail_seconds = round(time.monotonic() - started, 3)
if status != 200 or not isinstance(detail, dict): fail(report, f"detail failed with {status}")
if (detail.get("match") or {}).get("canonicalId") != match_id: fail(report, "detail returned a different canonical match")

lineups = detail.get("lineups") or []
lineup_summaries = [lineup_summary(x) for x in lineups if isinstance(x, dict)]
stat_summaries = []
for row in detail.get("statistics") or []:
    if not isinstance(row, dict): continue
    team = row.get("team") or {}; stats = row.get("statistics") or []
    stat_summaries.append({"team": team.get("name") if isinstance(team, dict) else None,
                           "teamId": team.get("id") if isinstance(team, dict) else None,
                           "statCount": len(stats)})
venue = detail.get("venue") or {}
officials = detail.get("officials") or []
report.update({"selectedDate": selected_date,
    "selectedMatch": {"id": match_id, "home": team_name(selected, "home"), "away": team_name(selected, "away"),
                      "status": status_code(selected), "sources": selected.get("sources") or [], "providerIds": selected.get("providerIds") or {},
                      "league": selected.get("league")},
    "detailStatus": status, "detailSeconds": detail_seconds, "maxDetailSeconds": MAX_DETAIL_SECONDS,
    "detail": {"events": len(detail.get("events") or []), "statistics": len(detail.get("statistics") or []), "lineups": len(lineups),
               "lineupQuality": lineup_summaries, "coachCoverage": sum(1 for x in lineup_summaries if x["coach"]),
               "statisticsQuality": stat_summaries, "venue": venue, "officials": officials,
               "coverage": detail.get("coverage") or {}, "source": detail.get("source"), "meta": detail.get("meta") or {}}})
save(report)

if detail_seconds > MAX_DETAIL_SECONDS: fail(report, f"match detail too slow: {detail_seconds}s > {MAX_DETAIL_SECONDS}s")
if len(lineup_summaries) < 2: fail(report, "both team lineups are required")
if any(x["starters"] < 11 or x["namedPlayers"] < 11 for x in lineup_summaries): fail(report, "incomplete starting lineups")
if any(x["substitutes"] < 1 for x in lineup_summaries): fail(report, "substitutes missing")
if sum(1 for x in lineup_summaries if x["coach"]) < 2: fail(report, "both head coaches are required")
if len(stat_summaries) < 2 or any(x["statCount"] < 5 for x in stat_summaries): fail(report, "team statistics incomplete")
if len(detail.get("events") or []) < 1: fail(report, "completed match has no events")
if not isinstance(venue, dict) or not venue.get("name"): fail(report, "venue missing")
if not any(isinstance(x, dict) and x.get("name") for x in officials): fail(report, "referee/official missing")

report["ok"] = True
report.pop("error", None)
save(report)
print(json.dumps(report, ensure_ascii=False, indent=2))
