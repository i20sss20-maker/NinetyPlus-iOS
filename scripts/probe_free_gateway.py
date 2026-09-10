"""Gate a release on actual public gateway data, not just a health response."""
import json, urllib.request
from pathlib import Path

base = 'https://ninetyplus-free.i20sss20.workers.dev'
results = []
def get(path):
    req = urllib.request.Request(base + path, headers={'Accept': 'application/json', 'User-Agent':'NinetyPlus-Free-QA/1.0'})
    with urllib.request.urlopen(req, timeout=25) as response:
        payload = json.load(response)
        results.append({'path':path,'status':response.status,'source':response.headers.get('X-90Plus-Source')})
        return payload
try:
    assert get('/api/health')['paidProviderEnabled'] is False
    teams = get('/free/espn/ksa.1/teams?limit=200')['sports'][0]['leagues'][0]['teams']
    assert any(x['team']['id'] == '2276' for x in teams)
    fixtures = get('/free/espn/uefa.champions/scoreboard?dates=20260909-20260910')['events']
    assert fixtures
    table = get('/free/espn/ksa.1/standings')
    assert table['children'][0]['standings']['entries']
    players = get('/free/directory/searchplayers.php?p=Cristiano%20Ronaldo')['player']
    assert any(x['idPlayer'] == '34146304' for x in players)
    print('PASS: deployed free gateway serves actual fixtures, Saudi clubs/table and player profiles; no paid key')
finally:
    Path('evidence').mkdir(exist_ok=True)
    Path('evidence/free-gateway-probe.json').write_text(json.dumps(results, indent=2))
