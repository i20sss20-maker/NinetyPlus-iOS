import { readFile, writeFile } from 'node:fs/promises';

const source = await readFile(new URL('./server.js', import.meta.url), 'utf8');
let s = source;

function replaceOnce(oldText, newText, label) {
  if (s.includes(newText)) return;
  if (!s.includes(oldText)) throw new Error(`v0.8 patch missing: ${label}`);
  s = s.replace(oldText, newText);
}

s = s.replaceAll('NinetyPlus-Backend/0.7', 'NinetyPlus-Backend/0.8');

// Broaden the free, no-key continuity layer. Unknown/unsupported ESPN league
// codes fail independently and are ignored by espnFixtures()' allSettled logic.
replaceOnce(
  "  { code:'afc.champions', apiFootballID:'17', name:'AFC Champions League' }\n];",
  "  { code:'afc.champions', apiFootballID:'17', name:'AFC Champions League' },\n  { code:'eng.2', apiFootballID:'40', name:'EFL Championship' },\n  { code:'ned.1', apiFootballID:'88', name:'Eredivisie' },\n  { code:'por.1', apiFootballID:'94', name:'Primeira Liga' },\n  { code:'tur.1', apiFootballID:'203', name:'Turkish Super Lig' },\n  { code:'sco.1', apiFootballID:'179', name:'Scottish Premiership' },\n  { code:'bel.1', apiFootballID:'144', name:'Belgian Pro League' },\n  { code:'usa.1', apiFootballID:'253', name:'Major League Soccer' },\n  { code:'mex.1', apiFootballID:'262', name:'Liga MX' },\n  { code:'bra.1', apiFootballID:'71', name:'Brazil Serie A' },\n  { code:'arg.1', apiFootballID:'128', name:'Argentina Liga Profesional' },\n  { code:'jpn.1', apiFootballID:'98', name:'J1 League' }\n];",
  'expanded ESPN league coverage'
);

replaceOnce(
  "let providerRequestsToday = 0;",
  "let providerRequestsToday = 0;\nlet providerRemoteBlocked = false;",
  'remote provider state'
);

replaceOnce(
  "  if (today !== providerBudgetDay) { providerBudgetDay = today; providerRequestsToday = 0; }\n}\nfunction providerBudgetAvailable() { resetProviderBudgetIfNeeded(); return providerRequestsToday < PROVIDER_DAILY_BUDGET; }",
  "  if (today !== providerBudgetDay) { providerBudgetDay = today; providerRequestsToday = 0; providerRemoteBlocked = false; }\n}\nfunction providerBudgetAvailable() { resetProviderBudgetIfNeeded(); return !providerRemoteBlocked && providerRequestsToday < PROVIDER_DAILY_BUDGET; }",
  'effective provider availability'
);

replaceOnce(
  "function noteProviderRequest() { resetProviderBudgetIfNeeded(); providerRequestsToday += 1; }",
  "function noteProviderRequest() { resetProviderBudgetIfNeeded(); providerRequestsToday += 1; }\nfunction providerBudgetRemaining() { resetProviderBudgetIfNeeded(); return providerRemoteBlocked ? 0 : Math.max(0, PROVIDER_DAILY_BUDGET - providerRequestsToday); }",
  'provider budget remaining'
);

replaceOnce(
`    const response = await fetchWithTimeout(upstream,{headers:{'x-apisports-key':key,accept:'application/json','user-agent':'NinetyPlus-Backend/0.8 Railway'}},12000);\n    const body = await response.text();\n    return {status:response.status,ok:response.ok,body,remaining:response.headers.get('x-ratelimit-requests-remaining')};`,
`    const response = await fetchWithTimeout(upstream,{headers:{'x-apisports-key':key,accept:'application/json','user-agent':'NinetyPlus-Backend/0.8 Railway'}},12000);\n    const body = await response.text();\n    let remoteDailyLimit = false;\n    try {\n      const payload = JSON.parse(body);\n      const errorText = JSON.stringify(payload?.errors || payload?.error || '').toLowerCase();\n      remoteDailyLimit = errorText.includes('request limit for the day') || (errorText.includes('requests') && errorText.includes('upgrade your plan'));\n    } catch {}\n    if (remoteDailyLimit) {\n      providerRemoteBlocked = true;\n      return {status:429,ok:false,body:JSON.stringify({error:'provider_daily_limit_reached'}),remaining:'0'};\n    }\n    return {status:response.status,ok:response.ok,body,remaining:response.headers.get('x-ratelimit-requests-remaining')};`,
  'upstream daily limit detection'
);

replaceOnce(
  "function normalizeESPNDetail(value) {",
  `function normalizeVenue(value) {\n  if (!value) return null;\n  const address=value.address || {};\n  const name=value.fullName || value.name || value.displayName || null;\n  const city=address.city || value.city || null;\n  const country=address.country || value.country || null;\n  if (!name && !city && !country) return null;\n  return {name,city,country};\n}\nfunction normalizeOfficials(value) {\n  return (Array.isArray(value)?value:[]).map(item=>({\n    name:item?.displayName || item?.fullName || item?.name || item?.athlete?.displayName || item?.athlete?.fullName || null,\n    role:item?.position?.displayName || item?.position?.name || item?.role || item?.type?.text || item?.type?.name || null\n  })).filter(item=>item.name);\n}\nfunction normalizeESPNDetail(value) {`,
  'detail normalizers'
);

replaceOnce(
  "  return {events,statistics:teams,lineups:rosters,venue:value?.header?.competitions?.[0]?.venue || value?.gameInfo?.venue || null,officials:value?.gameInfo?.officials || [],source:'espn'};",
  "  return {events,statistics:teams,lineups:rosters,venue:normalizeVenue(value?.header?.competitions?.[0]?.venue || value?.gameInfo?.venue),officials:normalizeOfficials(value?.gameInfo?.officials),source:'espn'};",
  'normalized venue officials'
);

// A valid match day with no returned games is not an outage. This matters when
// the API-Football daily allowance is exhausted but ESPN legitimately has no
// events for the selected day. Return [] and expose provider state in metadata.
replaceOnce(
  "  if (!matches.length && apiError) throw apiError;\n  const payload={date,timezone:'UTC',generatedAt:new Date().toISOString(),matches,meta:{apiFootballCount:api.length,espnCount:espn.length,canonicalCount:matches.length,providerBudgetRemaining:Math.max(0,PROVIDER_DAILY_BUDGET-providerRequestsToday)}};",
  "  if (!matches.length && apiError) console.warn('canonical fixture primary unavailable',{date,message:apiError?.message});\n  const payload={date,timezone:'UTC',generatedAt:new Date().toISOString(),matches,meta:{apiFootballCount:api.length,espnCount:espn.length,canonicalCount:matches.length,providerBudgetRemaining:providerBudgetRemaining(),primaryUnavailable:Boolean(apiError),emptyDay:matches.length===0}};",
  'empty day is valid'
);

replaceOnce(
`async function apiMatchDetail(match) {\n  const id=match?.providerIds?.apiFootball; if(!id) return null;\n  const [events,statistics,lineups]=await Promise.allSettled([\n    apiFootballJSON('fixtures/events',{fixture:id}),apiFootballJSON('fixtures/statistics',{fixture:id}),apiFootballJSON('fixtures/lineups',{fixture:id})\n  ]);\n  return {\n    events:events.status==='fulfilled'?(events.value.response||[]):[],\n    statistics:statistics.status==='fulfilled'?(statistics.value.response||[]):[],\n    lineups:lineups.status==='fulfilled'?(lineups.value.response||[]):[],source:'api-football'\n  };\n}`,
`async function apiMatchDetail(match, needs={events:true,statistics:true,lineups:true}) {\n  const id=match?.providerIds?.apiFootball; if(!id || providerBudgetRemaining() <= 0) return null;\n  const result={events:[],statistics:[],lineups:[],source:'api-football'};\n  const jobs=[];\n  if (needs.events && providerBudgetRemaining() > jobs.length) jobs.push(['events','fixtures/events']);\n  if (needs.statistics && providerBudgetRemaining() > jobs.length) jobs.push(['statistics','fixtures/statistics']);\n  if (needs.lineups && providerBudgetRemaining() > jobs.length) jobs.push(['lineups','fixtures/lineups']);\n  const settled=await Promise.allSettled(jobs.map(([,path])=>apiFootballJSON(path,{fixture:id})));\n  settled.forEach((entry,index)=>{ if(entry.status==='fulfilled') result[jobs[index][0]]=entry.value.response||[]; });\n  return result;\n}`,
  'budget aware API detail'
);

replaceOnce(
`async function canonicalMatchDetail(id) {\n  let match=canonicalMatchIndex.get(id);\n  if (!match) throw Object.assign(new Error('match_not_indexed'),{status:404});\n  const cacheKey=\`v2:match:\${id}\`; const cached=getCached(cacheKey); if(cached) return JSON.parse(cached.body);\n  const espnPromise=espnMatchDetail(match).catch(()=>null);\n  let api=null; try { api=await apiMatchDetail(match); } catch { api=null; }\n  const espn=await espnPromise;\n  const detail={match,...mergeMatchDetails(api,espn),generatedAt:new Date().toISOString()};\n  putCache(cacheKey,{status:200,ok:true,body:JSON.stringify(detail)},20);\n  return detail;\n}`,
`async function canonicalMatchDetail(id,date) {\n  let match=canonicalMatchIndex.get(id);\n  if (!match && /^\\d{4}-\\d{2}-\\d{2}$/.test(String(date||''))) {\n    try { await canonicalFixtures(String(date)); } catch {}\n    match=canonicalMatchIndex.get(id);\n  }\n  if (!match) throw Object.assign(new Error('match_not_indexed'),{status:404});\n  const cacheKey=\`v2:match:\${id}\`; const cached=getCached(cacheKey); if(cached) return JSON.parse(cached.body);\n  const espn=await espnMatchDetail(match).catch(()=>null);\n  const needs={events:!(espn?.events?.length),statistics:!(espn?.statistics?.length),lineups:!(espn?.lineups?.length)};\n  let api=null;\n  if ((needs.events || needs.statistics || needs.lineups) && providerBudgetRemaining()>0) {\n    try { api=await apiMatchDetail(match,needs); } catch { api=null; }\n  }\n  const detail={match,...mergeMatchDetails(api,espn),generatedAt:new Date().toISOString(),meta:{providerBudgetRemaining:providerBudgetRemaining(),providerRemoteBlocked}};\n  putCache(cacheKey,{status:200,ok:true,body:JSON.stringify(detail)},20);\n  return detail;\n}`,
  'self healing canonical match detail'
);

replaceOnce(
  "return sendJson(res,200,{ok:true,service:'ninetyplus-backend',version:'0.7'",
  "return sendJson(res,200,{ok:true,service:'ninetyplus-backend',version:'0.8.2'",
  'health version'
);

replaceOnce(
  "providerRequestsToday,providerDailyBudget:PROVIDER_DAILY_BUDGET,time:new Date().toISOString()",
  "providerRequestsToday,providerDailyBudget:PROVIDER_DAILY_BUDGET,providerRemoteBlocked,providerBudgetRemaining:providerBudgetRemaining(),time:new Date().toISOString()",
  'health upstream state'
);

replaceOnce(
  "await canonicalMatchDetail(id)",
  "await canonicalMatchDetail(id,String(url.searchParams.get('date')||''))",
  'match date forwarding'
);

s = s.replace("90+ backend v0.7 listening", "90+ backend v0.8.2 listening");

const generated = new URL('./.generated-server-v08.js', import.meta.url);
await writeFile(generated, s, 'utf8');
await import(generated.href + `?v=${Date.now()}`);
