"""Bounded, read-only diagnostics. Do not mistake HTTP 200 for usable data."""
import json, urllib.request, urllib.parse, datetime, xml.etree.ElementTree as ET
BASE = 'https://ninetyplus-ios-production.up.railway.app/'
report = {'checkedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'footballRequests': 0, 'checks': [], 'feeds': []}
def get(url):
    try:
        request = urllib.request.Request(url, headers={'User-Agent': 'NinetyPlus-QA/1.0', 'Accept': '*/*'})
        with urllib.request.urlopen(request, timeout=18) as response:
            return response.status, response.read(4000001), dict(response.headers)
    except Exception as error:
        return getattr(error, 'code', None), b'', {'error': str(error)}
status, body, _ = get(BASE + 'api/health')
try: health = json.loads(body)
except Exception: health = {}
report['health'] = {'status': status, **{key: health.get(key) for key in ['ok', 'providerRequestsToday', 'providerDailyBudget']}}
if health.get('ok') and health.get('providerRequestsToday', 90) + 3 <= health.get('providerDailyBudget', 0):
    today = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=3))).date()
    season = today.year if today.month >= 7 else today.year - 1
    for query in [{'path': 'fixtures', 'date': str(today), 'timezone': 'Asia/Riyadh'}, {'path': 'standings', 'league': '307', 'season': str(season)}, {'path': 'fixtures', 'team': '2939', 'next': '10'}]:
        status, body, headers = get(BASE + 'api/football?' + urllib.parse.urlencode(query))
        report['footballRequests'] += 1
        try: value = json.loads(body)
        except Exception: value = {}
        result = value.get('response')
        report['checks'].append({'query': query, 'status': status, 'cache': headers.get('X-90Plus-Cache'), 'errors': value.get('errors') or value.get('error'), 'count': len(result) if isinstance(result, list) else None, 'sample': result[:1] if isinstance(result, list) else None})
for name, url in [('saudi-google', 'https://news.google.com/rss/search?' + urllib.parse.urlencode({'q': 'دوري روشن OR الدوري السعودي', 'hl':'ar', 'gl':'SA', 'ceid':'SA:ar'})), ('filgoal-arab', 'https://www.filgoal.com/section/9/rss/' + urllib.parse.quote('الوطن-العربي'))]:
    status, body, headers = get(url)
    entry = {'name': name, 'status': status}
    try:
        root = ET.fromstring(body)
        items = root.findall('.//item')
        images = []
        import re
        for item in items:
            candidates = [node.attrib.get('url') for node in item.iter() if node.tag.endswith('thumbnail') or node.tag.endswith('enclosure') or node.tag.endswith('content')]
            html = ''.join(item.itertext())
            candidates += re.findall(r'<img[^>]+src=[\"\x27]([^\"\x27]+)', html)
            images.extend([candidate for candidate in candidates if candidate and candidate.startswith(('http://','https://'))])
        entry.update({'items': len(items), 'imageCandidates': len(images)})
        if images:
            image_status, image_body, image_headers = get(images[0])
            entry['firstImage'] = {'status': image_status, 'bytes':len(image_body), 'type':image_headers.get('Content-Type')}
    except Exception as error: entry['parseError'] = str(error)
    report['feeds'].append(entry)
print(json.dumps(report, ensure_ascii=False, indent=2))
