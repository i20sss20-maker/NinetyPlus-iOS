"""Report provider restrictions separately from successful production queries."""
import datetime
import json
import os
from pathlib import Path
import urllib.error
import urllib.parse
import urllib.request

BASE = 'https://ninetyplus-ios-production.up.railway.app'


def get_json(url):
    request = urllib.request.Request(url, headers={
        'User-Agent': 'NinetyPlus-QA/1.0', 'Accept': 'application/json',
    })
    try:
        with urllib.request.urlopen(request, timeout=18) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        try:
            payload = json.loads(error.read())
        except (ValueError, OSError):
            payload = {'transportError': str(error)}
        return error.code, payload
    except Exception as error:
        return None, {'transportError': str(error)}


def available_budget(health):
    values = [health.get('providerRequestsToday'), health.get('providerDailyBudget')]
    if 'providerBudgetRemaining' in health:
        values.append(health['providerBudgetRemaining'])
    if any(type(value) is not int or value < 0 for value in values):
        raise ValueError('Provider budget metadata is missing or invalid.')
    remaining = max(0, values[1] - values[0])
    return min(remaining, values[2]) if len(values) == 3 else remaining


def probe(fetch=get_json, today=None):
    status, health = fetch(BASE + '/api/health')
    report = {'healthStatus': status, 'health': health, 'outcome': 'failed', 'checks': []}
    if status != 200 or not isinstance(health, dict) or health.get('ok') is not True:
        report['reason'] = 'Backend health was not a valid successful response.'
        return report
    if health.get('providerConfigured') is False:
        report.update(outcome='skipped', reason='Provider is not configured; queries were NOT verified.')
        return report
    if health.get('providerRemoteBlocked') is True:
        report.update(outcome='skipped', reason='Provider is remotely blocked; queries were NOT verified.')
        return report
    try:
        remaining = available_budget(health)
    except ValueError as error:
        report['reason'] = str(error)
        return report
    if remaining < 3:
        report.update(outcome='skipped', reason='Fewer than three provider requests remain; queries were NOT verified.')
        return report
    if today is None:
        today = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=3))).date()
    queries = [
        {'path': 'teams', 'search': 'Ittihad'},
        {'path': 'fixtures', 'date': str(today + datetime.timedelta(days=1)), 'timezone': 'Asia/Riyadh'},
        {'path': 'fixtures', 'date': str(today - datetime.timedelta(days=1)), 'timezone': 'Asia/Riyadh'},
    ]
    for query in queries:
        status, payload = fetch(BASE + '/api/football?' + urllib.parse.urlencode(query))
        data = payload if isinstance(payload, dict) else {}
        rows = data.get('response')
        errors = data.get('errors') or data.get('error') or data.get('transportError')
        valid = status == 200 and not errors and isinstance(rows, list)
        valid = valid and all(isinstance(row, dict) for row in rows)
        if valid and query['path'] == 'teams':
            valid = bool(rows) and all(
                isinstance(row.get('team'), dict) and row['team'].get('id') is not None
                for row in rows
            )
        record = {
            'query': query, 'status': status, 'outcome': 'passed' if valid else 'failed',
            'errors': errors, 'count': len(rows) if isinstance(rows, list) else None,
        }
        if not valid:
            record['responseBody'] = payload
            report['checks'].append(record)
            report['reason'] = 'A provider query failed or returned an invalid payload; remaining queries were not sent.'
            return report
        if query['path'] == 'teams':
            record['teams'] = [row['team'] for row in rows]
        else:
            record['sample'] = rows[:1]
        report['checks'].append(record)
    report.update(outcome='passed', reason='All three provider queries returned valid successful responses.')
    return report


def exit_code(report):
    return 0 if report['outcome'] in ('passed', 'skipped') else 1


def main():
    report = probe()
    destination = Path('evidence/free-plan-queries.json')
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if report['outcome'] == 'skipped':
        print('::warning::' + report['reason'])
    elif report['outcome'] == 'failed':
        print('::error::' + report['reason'])
    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary:
        with open(summary, 'a', encoding='utf-8') as output:
            output.write('\n### API-Football provider queries: ' + report['outcome'].upper())
            output.write('\n\n' + report['reason'] + '\n')
            output.write('\nQueries attempted: ' + str(len(report['checks'])) + ' / 3.\n')
            output.write('\nThis diagnostic does not establish full app or physical-device coverage.\n')
    return exit_code(report)


if __name__ == '__main__':
    raise SystemExit(main())
