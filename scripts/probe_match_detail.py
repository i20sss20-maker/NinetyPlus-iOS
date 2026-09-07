import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

BASE = "https://ninetyplus-ios-production.up.railway.app"
OUT = Path("evidence/production-match-detail.json")
OUT.parent.mkdir(parents=True, exist_ok=True)


def get_json(path, params=None, timeout=20):
    query = ("?" + urlencode(params)) if params else ""
    req = Request(BASE + path + query, headers={"User-Agent": "NinetyPlus-QA/1.1"})
    with urlopen(req, timeout=timeout) as response:
        return response.status, json.load(response)


def matches_from(payload):
    if isinstance(payload, dict):
        for key in ("matches", "fixtures", "response", "data"):
            value = payload.get(key)
            if isinstance(value, list):
                return value
    return payload if isinstance(payload, list) else []


def status_code(match):
    value = match.get("status") or match.get("state") or ""
    if isinstance(value, dict):
        return str(value.get("code") or value.get("text") or "").lower()
    return str(value).lower()


def is_finished(match):
    status = status_code(match)
    return any(token in status for token in ("ft", "finished", "full time", "aet", "pen"))


def team_name(match, side):
    value = match.get(side) or match.get(side + "Team")
    if isinstance(value, dict):
        return value.get("name") or value.get("displayName") or value.get("shortDisplayName")
    return value


report = {"checkedAt": datetime.now(timezone.utc).isoformat(), "base": BASE, "days": []}
selected = None
selected_date = None

for offset in range(0, 8):
    day = (datetime.now(timezone.utc) - timedelta(days=offset)).date().isoformat()
    try:
        status, payload = get_json("/api/v2/fixtures", {"date": day})
        matches = matches_from(payload)
        report["days"].append({
            "date": day,
            "status": status,
            "count": len(matches),
            "canonicalCount": (payload.get("meta") or {}).get("canonicalCount") if isinstance(payload, dict) else None,
        })
        if matches and selected is None:
            selected = next((m for m in matches if is_finished(m)), matches[0])
            selected_date = day
            if is_finished(selected):
                break
    except Exception as exc:
        report["days"].append({"date": day, "error": str(exc)})

if not selected:
    report["ok"] = False
    report["error"] = "No fixture found in the last 8 days"
    OUT.write_text(json.dumps(report, ensure_ascii=False, indent=2))
    raise SystemExit("production match probe: no fixture found")

match_id = (
    selected.get("canonicalId")
    or selected.get("id")
    or selected.get("matchID")
    or selected.get("matchId")
)
if not match_id or not str(match_id).startswith("np:"):
    report["ok"] = False
    report["error"] = "Selected fixture had no canonical id"
    report["selected"] = selected
    OUT.write_text(json.dumps(report, ensure_ascii=False, indent=2))
    raise SystemExit("production match probe: canonical fixture id missing")

status, detail = get_json("/api/v2/match", {"id": str(match_id), "date": selected_date})
if status != 200 or not isinstance(detail, dict):
    raise SystemExit(f"production match probe: detail failed with {status}")

coverage = detail.get("coverage") or {}
match_payload = detail.get("match") or {}
if match_payload.get("canonicalId") != match_id:
    raise SystemExit("production match probe: detail returned a different canonical match")

report.update({
    "ok": True,
    "selectedDate": selected_date,
    "selectedMatch": {
        "id": match_id,
        "home": team_name(selected, "home"),
        "away": team_name(selected, "away"),
        "status": status_code(selected),
        "sources": selected.get("sources") or [],
        "providerIds": selected.get("providerIds") or {},
    },
    "detailStatus": status,
    "detail": {
        "events": len(detail.get("events") or []),
        "statistics": len(detail.get("statistics") or []),
        "lineups": len(detail.get("lineups") or []),
        "venue": detail.get("venue"),
        "officials": detail.get("officials") or [],
        "coverage": coverage,
        "source": detail.get("source"),
        "meta": detail.get("meta") or {},
    },
})

OUT.write_text(json.dumps(report, ensure_ascii=False, indent=2))
print(json.dumps(report, ensure_ascii=False, indent=2))
