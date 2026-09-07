"""Read-only diagnostics: use published feeds and actual provider response bodies."""
import json, urllib.request, urllib.parse, datetime, xml.etree.ElementTree as ET, pathlib, re
BASE='https://ninetyplus-ios-production.up.railway.app/'
report={'checkedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'footballRequests':0,'checks':[],'feeds':[]}
def get(url):
    parts=urllib.parse.urlsplit(url)
    url=urllib.parse.urlunsplit((parts.scheme,parts.netloc,urllib.parse.quote(parts.path,safe='/%'),parts.query,''))
    try:
        req=urllib.request.Request(url,headers={'User-Agent':'NinetyPlus-QA/1.0','Accept':'*/*'})
        with urllib.request.urlopen(req,timeout=18) as response: return response.status,response.read(4000001),dict(response.headers)
    except Exception as error: return getattr(error,'code',None),b'',{'error':str(error)}
status,body,_=get(BASE+'api/health')
try: health=json.loads(body)
except Exception: health={}
report['health']={'status':status,**{k:health.get(k) for k in ['ok','providerRequestsToday','providerDailyBudget']}}
if health.get('ok') and health.get('providerRequestsToday',90)+2 <= health.get('providerDailyBudget',0):
    today=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=3))).date()
    for query in [{'path':'teams','search':'Ittihad'},{'path':'fixtures','date':str(today+datetime.timedelta(days=1)),'timezone':'Asia/Riyadh'}]:
        status,body,headers=get(BASE+'api/football?'+urllib.parse.urlencode(query)); report['footballRequests']+=1
        try: value=json.loads(body)
        except Exception: value={}
        result=value.get('response',[])
        check={'query':query,'status':status,'errors':value.get('errors') or value.get('error'),'count':len(result) if isinstance(result,list) else None}
        if query['path']=='teams': check['saudiClubPresent']=any(x.get('team',{}).get('id')==2938 for x in result)
        report['checks'].append(check)
for name,url in [('hihi2','https://hihi2.com/feed'),('france24','https://www.france24.com/ar/رياضة/rss')]:
    status,body,headers=get(url); entry={'name':name,'status':status}
    try:
        root=ET.fromstring(body); items=root.findall('.//item'); images=[]
        for item in items:
            candidates=[n.attrib.get('url') for n in item.iter() if n.tag.endswith(('thumbnail','enclosure','content'))]
            candidates+=re.findall(r'<img[^>]+src=[\"\x27]([^\"\x27]+)', ''.join(item.itertext()))
            images.extend([v for v in candidates if v and v.startswith(('https://','http://'))])
        entry.update({'items':len(items),'imageCandidates':len(images)})
        if images:
            s,d,h=get(images[0]); entry['firstImage']={'status':s,'bytes':len(d),'type':h.get('Content-Type')}
    except Exception as error: entry['error']=str(error)
    report['feeds'].append(entry)
status,body,headers=get('https://site.web.api.espn.com/apis/v2/sports/soccer/ksa.1/standings')
try:
    value=json.loads(body)
    report['table']={'status':status,'season':value.get('season'),'rows':sum(len(g.get('standings',{}).get('entries',[])) for g in value.get('children',[]))}
    pathlib.Path('evidence/public-table.json').write_bytes(body)
except Exception as error: report['table']={'status':status,'error':str(error)}
print(json.dumps(report,ensure_ascii=False,indent=2))
