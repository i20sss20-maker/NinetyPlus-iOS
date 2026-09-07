"""Read-only production probe: health plus at most two football GETs; no retries.
No provider key is read or required. Exit failure never implies an iOS build failure.
"""
from __future__ import annotations
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

BASE = 'https://ninetyplus-ios-production.up.railway.app'
REPORT = Path('/tmp/ninetyplus-service-probe.json')


def get(path: str) -> dict:
    request = urllib.request.Request(BASE + path, headers={
        'User-Agent': 'NinetyPlus-ReadOnly-Probe/1.0', 'Accept': 'application/json'
    })
    try:
        try:
            response = urllib.request.urlopen(request, timeout=20)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            data = response.read(2_000_000)
            try:
                payload = json.loads(data)
            except (ValueError, UnicodeError):
                payload = None
            return {'status': response.code, 'cache': response.headers.get('X-90Plus-Cache'), 'payload': payload}
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        return {'status': None, 'transportError': type(error).__name__, 'payload': None}


def summarize(result: dict, entity: str) -> dict:
    payload = result.get('payload')
    data = payload if isinstance(payload, dict) else {}
    errors = data.get('errors') or data.get('error')
    rows = data.get('response')
    names = []
    if isinstance(rows, list):
        for row in rows[:2]:
            if isinstance(row, dict) and isinstance(row.get(entity), dict):
                name = row[entity].get('name')
                if isinstance(name, str):
                    names.append(name)
    ok = result.get('status') == 200 and not errors and isinstance(rows, list) and bool(rows) and bool(names)
    # Never log the response's credentials, headers, or unfiltered body.
    error_keys = sorted(errors.keys()) if isinstance(errors, dict) else ([] if not errors else ['provider_error'])
    return {'ok': ok, 'status': result.get('status'), 'cache': result.get('cache'),
            'errorKeys': error_keys, 'resultCount': len(rows) if isinstance(rows, list) else None,
            'names': names, 'transportError': result.get('transportError')}


def probe(fetch=get) -> dict:
    report = {'checkedAt': datetime.now(timezone.utc).isoformat(), 'footballRequests': 0, 'ok': False}
    response = fetch('/api/health')
    payload = response.get('payload')
    data = payload if isinstance(payload, dict) else {}
    allowed = ['ok', 'providerConfigured', 'providerRequestsToday', 'providerDailyBudget', 'version']
    report['health'] = {key: data.get(key) for key in allowed}
    report['health']['status'] = response.get('status')
    if response.get('status') != 200 or data.get('ok') is not True or data.get('providerConfigured') is not True:
        report['reason'] = 'Health/configuration check failed; no football requests made.'
        return report
    used, budget = data.get('providerRequestsToday'), data.get('providerDailyBudget')
    if isinstance(used, (int, float)) and isinstance(budget, (int, float)) and budget - used < 2:
        report['reason'] = 'Insufficient remaining daily budget; no football requests made.'
        return report
    report['checks'] = []
    for path, term, entity in [('teams', 'Al Ittihad', 'team'), ('players/profiles', 'Ronaldo', 'player')]:
        route = '/api/football?' + urllib.parse.urlencode({'path': path, 'search': term})
        check = summarize(fetch(route), entity)
        report['footballRequests'] += 1
        report['checks'].append({'path': path, **check})
    report['ok'] = all(check['ok'] for check in report['checks'])
    return report


if __name__ == '__main__':
    result = probe()
    REPORT.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(REPORT.read_text(encoding='utf-8'))
    sys.exit(0 if result['ok'] else 1)
