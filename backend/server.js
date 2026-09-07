import http from 'node:http';
import { randomUUID, createHash } from 'node:crypto';

const API_BASE = 'https://v3.football.api-sports.io';
const ESPN_SITE = 'https://site.api.espn.com/apis/site/v2/sports/soccer';
const PORT = Number(process.env.PORT || 3000);
const CACHE_LIMIT = 800;
const RESPONSE_RATE_LIMIT = Number(process.env.RESPONSE_RATE_LIMIT || 120);
const PROVIDER_DAILY_BUDGET = Number(process.env.PROVIDER_DAILY_BUDGET || 90);
const responseCache = new Map();
const inFlight = new Map();
const clientWindows = new Map();
const canonicalMatchIndex = new Map();
let providerBudgetDay = new Date().toISOString().slice(0, 10);
let providerRequestsToday = 0;

const ESPN_LEAGUES = [
  { code:'ksa.1', apiFootballID:'307', name:'Saudi Pro League' },
  { code:'eng.1', apiFootballID:'39', name:'Premier League' },
  { code:'esp.1', apiFootballID:'140', name:'La Liga' },
  { code:'ita.1', apiFootballID:'135', name:'Serie A' },
  { code:'ger.1', apiFootballID:'78', name:'Bundesliga' },
  { code:'fra.1', apiFootballID:'61', name:'Ligue 1' },
  { code:'uefa.champions', apiFootballID:'2', name:'UEFA Champions League' },
  { code:'uefa.europa', apiFootballID:'3', name:'UEFA Europa League' },
  { code:'uefa.europa.conf', apiFootballID:'848', name:'UEFA Conference League' },
  { code:'afc.champions', apiFootballID:'17', name:'AFC Champions League' }
];

const ALLOWED_PATHS = new Set([
  'fixtures','standings','teams','players/profiles','players/topscorers','players',
  'fixtures/events','fixtures/statistics','fixtures/lineups','fixtures/headtohead'
]);
const ALLOWED_QUERY_KEYS = new Set([
  'id','date','timezone','live','league','season','last','next','team','search','player','fixture','h2h','page'
]);

function cacheSeconds(path, query) {
  if (path === 'fixtures' && (query.live || query.id)) return 15;
  if (path === 'fixtures/events') return 15;
  if (path === 'fixtures/statistics') return 20;
  if (path === 'fixtures/lineups') return 600;
  if (path === 'fixtures/headtohead') return 1800;
  if (path === 'fixtures' && query.date) return 60;
  if (path === 'standings') return 600;
  if (path === 'players/topscorers') return 600;
  if (path === 'players' || path === 'players/profiles') return 1800;
  if (path === 'teams') return 21600;
  return 120;
}

function sendJson(res, status, payload, extraHeaders = {}) { sendBody(res, status, JSON.stringify(payload), extraHeaders); }
function sendBody(res, status, body, extraHeaders = {}) {
  res.writeHead(status, {
    'Content-Type':'application/json; charset=utf-8','Content-Length':Buffer.byteLength(body),
    'X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer','Access-Control-Allow-Origin':'*',...extraHeaders
  });
  res.end(body);
}
function clientAddress(req) {
  const forwarded = String(req.headers['x-forwarded-for'] || '').split(',')[0].trim();
  return forwarded || req.socket.remoteAddress || 'unknown';
}
function allowClient(req) {
  const now = Date.now(); const key = clientAddress(req); const current = clientWindows.get(key);
  if (!current || now - current.startedAt >= 60_000) { clientWindows.set(key,{startedAt:now,count:1}); return true; }
  current.count += 1; return current.count <= RESPONSE_RATE_LIMIT;
}
function resetProviderBudgetIfNeeded() {
  const today = new Date().toISOString().slice(0,10);
  if (today !== providerBudgetDay) { providerBudgetDay = today; providerRequestsToday = 0; }
}
function providerBudgetAvailable() { resetProviderBudgetIfNeeded(); return providerRequestsToday < PROVIDER_DAILY_BUDGET; }
function noteProviderRequest() { resetProviderBudgetIfNeeded(); providerRequestsToday += 1; }
function normalizeRequest(url) {
  const path = String(url.searchParams.get('path') || '').replace(/^\/+/, '');
  if (!ALLOWED_PATHS.has(path)) return { error:'unsupported_path' };
  const upstream = new URL(`${API_BASE}/${path}`); const safeQuery = {};
  for (const [name,value] of url.searchParams.entries()) {
    if (name === 'path' || !ALLOWED_QUERY_KEYS.has(name)) continue;
    const text = String(value).trim(); if (!text || text.length > 120) continue;
    upstream.searchParams.set(name,text); safeQuery[name] = text;
  }
  upstream.searchParams.sort();
  return { path,safeQuery,upstream,cacheKey:`${path}?${upstream.searchParams.toString()}` };
}
function getCached(cacheKey) {
  const entry = responseCache.get(cacheKey); if (!entry || entry.expiresAt <= Date.now()) return null;
  entry.lastAccess = Date.now(); return entry;
}
function getStale(cacheKey) {
  const entry = responseCache.get(cacheKey); if (!entry) return null;
  const maxStaleMs = Math.max(entry.ttl * 12,300) * 1000;
  return Date.now() - entry.expiresAt > maxStaleMs ? null : entry;
}
function putCache(cacheKey,result,ttl) {
  if (responseCache.size >= CACHE_LIMIT && !responseCache.has(cacheKey)) {
    const oldest = [...responseCache.entries()].sort((a,b)=>a[1].lastAccess-b[1].lastAccess)[0];
    if (oldest) responseCache.delete(oldest[0]);
  }
  responseCache.set(cacheKey,{...result,ttl,expiresAt:Date.now()+ttl*1000,lastAccess:Date.now()});
}
async function fetchWithTimeout(url, options = {}, ms = 12000) {
  const controller = new AbortController(); const timeout = setTimeout(()=>controller.abort(),ms);
  try { return await fetch(url,{...options,signal:controller.signal}); }
  finally { clearTimeout(timeout); }
}
async function fetchProvider(upstream,key,requestId) {
  if (!providerBudgetAvailable()) { const error = new Error('provider_daily_budget_exhausted'); error.budgetExhausted = true; throw error; }
  noteProviderRequest();
  try {
    const response = await fetchWithTimeout(upstream,{headers:{'x-apisports-key':key,accept:'application/json','user-agent':'NinetyPlus-Backend/0.7 Railway'}},12000);
    const body = await response.text();
    return {status:response.status,ok:response.ok,body,remaining:response.headers.get('x-ratelimit-requests-remaining')};
  } catch (error) {
    const timedOut = error?.name === 'AbortError'; console.error('football provider failed',{requestId,timedOut,message:error?.message});
    throw Object.assign(error,{timedOut});
  }
}
async function apiFootballJSON(path, query = {}) {
  const key = process.env.API_FOOTBALL_KEY;
  if (!key) throw Object.assign(new Error('sports_provider_not_configured'),{providerUnavailable:true});
  const upstream = new URL(`${API_BASE}/${path}`);
  for (const [k,v] of Object.entries(query)) if (v !== undefined && v !== null && String(v) !== '') upstream.searchParams.set(k,String(v));
  upstream.searchParams.sort();
  const cacheKey = `internal:${path}?${upstream.searchParams.toString()}`;
  const ttl = cacheSeconds(path,query); const cached = getCached(cacheKey);
  if (cached) return JSON.parse(cached.body);
  const requestId = randomUUID();
  const result = await fetchProvider(upstream,key,requestId);
  if (!result.ok) throw Object.assign(new Error(`provider_http_${result.status}`),{providerStatus:result.status});
  putCache(cacheKey,result,ttl);
  const value = JSON.parse(result.body);
  if (value?.errors && (Array.isArray(value.errors) ? value.errors.length : Object.keys(value.errors).length)) {
    throw Object.assign(new Error('provider_payload_error'),{providerErrors:value.errors});
  }
  return value;
}
async function handleFootball(req,res,url) {
  const requestId = randomUUID(); const key = process.env.API_FOOTBALL_KEY;
  if (!key) return sendJson(res,503,{error:'sports_provider_not_configured',requestId},{'Cache-Control':'no-store'});
  const normalized = normalizeRequest(url);
  if (normalized.error) return sendJson(res,400,{error:normalized.error,requestId},{'Cache-Control':'no-store'});
  const {path,safeQuery,upstream,cacheKey} = normalized; const ttl = cacheSeconds(path,safeQuery); const cached = getCached(cacheKey);
  if (cached) return sendBody(res,cached.status,cached.body,{'Cache-Control':`public, max-age=${ttl}, stale-while-revalidate=${Math.max(ttl*3,60)}`,'X-90Plus-Request-ID':requestId,'X-90Plus-Source':'api-football','X-90Plus-Cache':'HIT'});
  try {
    let promise = inFlight.get(cacheKey);
    if (!promise) { promise = fetchProvider(upstream,key,requestId); inFlight.set(cacheKey,promise); }
    const result = await promise; inFlight.delete(cacheKey); if (result.ok) putCache(cacheKey,result,ttl);
    const headers = {'Cache-Control':result.ok?`public, max-age=${ttl}, stale-while-revalidate=${Math.max(ttl*3,60)}`:'no-store','X-90Plus-Request-ID':requestId,'X-90Plus-Source':'api-football','X-90Plus-Cache':'MISS'};
    if (result.remaining) headers['X-90Plus-Provider-Remaining'] = result.remaining;
    return sendBody(res,result.status,result.body,headers);
  } catch (error) {
    inFlight.delete(cacheKey); const stale = getStale(cacheKey);
    if (stale) return sendBody(res,stale.status,stale.body,{'Cache-Control':'no-store','X-90Plus-Request-ID':requestId,'X-90Plus-Source':'api-football','X-90Plus-Cache':'STALE'});
    if (error?.budgetExhausted) return sendJson(res,429,{error:'provider_daily_budget_exhausted',requestId},{'Cache-Control':'no-store','Retry-After':'3600','X-90Plus-Request-ID':requestId});
    return sendJson(res,error?.timedOut?504:502,{error:error?.timedOut?'sports_provider_timeout':'sports_provider_unavailable',requestId},{'Cache-Control':'no-store','X-90Plus-Request-ID':requestId});
  }
}

function cleanName(value='') {
  return String(value).normalize('NFKD').replace(/[\u0300-\u036f]/g,'').toLowerCase()
    .replace(/\b(fc|cf|sc|club|football|saudi)\b/g,' ').replace(/[^a-z0-9\u0600-\u06ff]+/g,' ').trim();
}
function canonicalKey(dateISO,home,away) {
  const day = String(dateISO || '').slice(0,10);
  return createHash('sha1').update(`${day}|${cleanName(home)}|${cleanName(away)}`).digest('hex').slice(0,16);
}
function parseScore(value) { const n = Number.parseInt(String(value ?? ''),10); return Number.isFinite(n) ? n : null; }
function apiStatus(item) {
  const s = item?.fixture?.status || {};
  return { code:s.short || s.long || 'TBD', text:s.long || s.short || null, elapsed:Number.isFinite(s.elapsed)?s.elapsed:null };
}
function normalizeAPIFixture(item) {
  const dateUTC = item?.fixture?.date ? new Date(item.fixture.date).toISOString() : null;
  const home = item?.teams?.home || {}, away = item?.teams?.away || {};
  return {
    canonicalId:`np:${canonicalKey(dateUTC,home.name,away.name)}`,
    dateUTC, league:{id:item?.league?.id?.toString() || null,code:null,name:item?.league?.name || 'Football',logo:item?.league?.logo || null,country:item?.league?.country || null},
    home:{id:home.id?.toString() || null,name:home.name || '—',logo:home.logo || null},
    away:{id:away.id?.toString() || null,name:away.name || '—',logo:away.logo || null},
    score:{home:Number.isFinite(item?.goals?.home)?item.goals.home:null,away:Number.isFinite(item?.goals?.away)?item.goals.away:null},
    status:apiStatus(item), providerIds:{apiFootball:item?.fixture?.id?.toString() || null,espn:null}, sources:['api-football'], quality:'single-source'
  };
}
function espnStatus(status) {
  const type = status?.type || {}; const state = String(type.state || '').toLowerCase();
  const text = [type.description,type.detail,type.name].filter(Boolean).join(' ').toLowerCase();
  let code = 'TBD';
  if (text.includes('postpon')) code='PST'; else if (text.includes('cancel')) code='CANC'; else if (text.includes('half')) code='HT';
  else if (type.completed || state==='post') code='FT'; else if (state==='in') code='LIVE'; else if (state==='pre') code='NS';
  const digits = String(status?.displayClock || '').match(/\d+/); const elapsed = state==='in' && digits ? Number(digits[0]) : null;
  return {code,text:type.description || type.detail || type.name || null,elapsed};
}
function normalizeESPNEvent(event, league) {
  const competition = event?.competitions?.[0]; if (!competition) return null;
  const homeC = competition.competitors?.find(c=>String(c.homeAway).toLowerCase()==='home');
  const awayC = competition.competitors?.find(c=>String(c.homeAway).toLowerCase()==='away');
  if (!homeC || !awayC) return null;
  const dateUTC = event.date ? new Date(event.date).toISOString() : null;
  const started = !['NS','TBD','PST','CANC'].includes(espnStatus(competition.status || event.status).code);
  const result = {
    canonicalId:`np:${canonicalKey(dateUTC,homeC.team?.displayName || homeC.team?.shortDisplayName,awayC.team?.displayName || awayC.team?.shortDisplayName)}`,
    dateUTC, league:{id:league.apiFootballID || null,code:league.code,name:league.name,logo:null,country:null},
    home:{id:homeC.id ? `espn:${league.code}:team:${homeC.id}` : null,name:homeC.team?.displayName || homeC.team?.shortDisplayName || '—',logo:homeC.team?.logo || null},
    away:{id:awayC.id ? `espn:${league.code}:team:${awayC.id}` : null,name:awayC.team?.displayName || awayC.team?.shortDisplayName || '—',logo:awayC.team?.logo || null},
    score:{home:started?parseScore(homeC.score):null,away:started?parseScore(awayC.score):null}, status:espnStatus(competition.status || event.status),
    providerIds:{apiFootball:null,espn:event.id ? String(event.id):null}, sources:['espn'], quality:'single-source'
  };
  return result;
}
async function espnScoreboard(league,date) {
  const ymd = String(date).replaceAll('-','');
  const url = `${ESPN_SITE}/${encodeURIComponent(league.code)}/scoreboard?dates=${encodeURIComponent(ymd)}`;
  const response = await fetchWithTimeout(url,{headers:{accept:'application/json','user-agent':'NinetyPlus-Backend/0.7'}},10000);
  if (!response.ok) throw new Error(`espn_${league.code}_${response.status}`);
  const value = await response.json();
  return (value.events || []).map(event=>normalizeESPNEvent(event,league)).filter(Boolean);
}
async function espnFixtures(date) {
  const groups = await Promise.allSettled(ESPN_LEAGUES.map(l=>espnScoreboard(l,date)));
  return groups.flatMap(g=>g.status==='fulfilled'?g.value:[]);
}
function sameFixture(a,b) {
  if (!a.dateUTC || !b.dateUTC) return false;
  const dt = Math.abs(new Date(a.dateUTC)-new Date(b.dateUTC));
  const exact = cleanName(a.home.name)===cleanName(b.home.name) && cleanName(a.away.name)===cleanName(b.away.name);
  const reversed = cleanName(a.home.name)===cleanName(b.away.name) && cleanName(a.away.name)===cleanName(b.home.name);
  return dt <= 20*60*1000 && (exact || reversed);
}
function mergeFixture(primary,secondary) {
  const api = primary.sources.includes('api-football')?primary:secondary;
  const espn = primary.sources.includes('espn')?primary:secondary;
  const merged = {
    ...api,
    canonicalId:api.canonicalId,
    league:{...espn.league,...api.league,code:espn.league.code || api.league.code},
    home:{...espn.home,...api.home,logo:api.home.logo || espn.home.logo},
    away:{...espn.away,...api.away,logo:api.away.logo || espn.away.logo},
    providerIds:{apiFootball:api.providerIds.apiFootball,espn:espn.providerIds.espn},
    sources:['api-football','espn'],quality:'verified'
  };
  const delta = Math.abs(new Date(api.dateUTC)-new Date(espn.dateUTC));
  if (delta > 2*60*1000) merged.warnings=['kickoff-source-conflict'];
  return merged;
}
function dedupeAndMerge(api,espn) {
  const output=[]; const used = new Set();
  for (const a of api) {
    const idx = espn.findIndex((e,i)=>!used.has(i)&&sameFixture(a,e));
    const item = idx>=0 ? (used.add(idx),mergeFixture(a,espn[idx])) : a;
    output.push(item); canonicalMatchIndex.set(item.canonicalId,item);
  }
  espn.forEach((e,i)=>{ if(!used.has(i)){ output.push(e); canonicalMatchIndex.set(e.canonicalId,e); } });
  return output.sort((a,b)=>String(a.dateUTC).localeCompare(String(b.dateUTC)) || a.canonicalId.localeCompare(b.canonicalId));
}
async function canonicalFixtures(date) {
  const cacheKey=`v2:fixtures:${date}`; const cached=getCached(cacheKey);
  if (cached) return JSON.parse(cached.body);
  const espnPromise=espnFixtures(date);
  let api=[]; let apiError=null;
  try {
    const value=await apiFootballJSON('fixtures',{date,timezone:'UTC'});
    api=(value.response||[]).map(normalizeAPIFixture);
  } catch(error) { apiError=error; }
  const espn=await espnPromise.catch(()=>[]);
  const matches=dedupeAndMerge(api,espn);
  if (!matches.length && apiError) throw apiError;
  const payload={date,timezone:'UTC',generatedAt:new Date().toISOString(),matches,meta:{apiFootballCount:api.length,espnCount:espn.length,canonicalCount:matches.length,providerBudgetRemaining:Math.max(0,PROVIDER_DAILY_BUDGET-providerRequestsToday)}};
  putCache(cacheKey,{status:200,ok:true,body:JSON.stringify(payload)},45);
  return payload;
}

function findESPNLeagueForMatch(match) {
  return ESPN_LEAGUES.find(l=>l.code===match?.league?.code || l.apiFootballID===match?.league?.id) || null;
}
function normalizeESPNDetail(value) {
  const events=(value?.keyEvents || value?.plays || []).map(x=>({
    minute:x?.clock?.displayValue || x?.clock || null,type:x?.type?.text || x?.type?.name || x?.type || null,text:x?.text || x?.shortText || null,
    team:x?.team?.displayName || x?.team?.name || null,player:x?.athletes?.[0]?.athlete?.displayName || x?.participants?.[0]?.athlete?.displayName || null
  }));
  const teams=(value?.boxscore?.teams || []).map(t=>({
    team:{id:t?.team?.id || null,name:t?.team?.displayName || t?.team?.name || null,logo:t?.team?.logo || null},
    statistics:(t?.statistics || []).map(s=>({name:s?.label || s?.name || null,value:s?.displayValue ?? s?.value ?? null}))
  }));
  const rosters=(value?.rosters || value?.boxscore?.players || []).map(r=>({
    team:{id:r?.team?.id || null,name:r?.team?.displayName || r?.team?.name || null,logo:r?.team?.logo || null},
    formation:r?.formation || r?.formations?.[0]?.name || null,
    players:(r?.roster || r?.statistics?.[0]?.athletes || r?.players || []).map(p=>({
      id:p?.athlete?.id || p?.id || null,name:p?.athlete?.displayName || p?.displayName || p?.name || null,
      jersey:p?.athlete?.jersey || p?.jersey || null,position:p?.athlete?.position?.abbreviation || p?.position?.abbreviation || p?.position || null,
      starter:p?.starter ?? p?.isStarter ?? null,subbedIn:p?.subbedIn ?? null,subbedOut:p?.subbedOut ?? null
    }))
  }));
  return {events,statistics:teams,lineups:rosters,venue:value?.header?.competitions?.[0]?.venue || value?.gameInfo?.venue || null,officials:value?.gameInfo?.officials || [],source:'espn'};
}
async function espnMatchDetail(match) {
  const league=findESPNLeagueForMatch(match); const eventId=match?.providerIds?.espn;
  if (!league || !eventId) return null;
  const url=`${ESPN_SITE}/${encodeURIComponent(league.code)}/summary?event=${encodeURIComponent(eventId)}`;
  const response=await fetchWithTimeout(url,{headers:{accept:'application/json','user-agent':'NinetyPlus-Backend/0.7'}},10000);
  if (!response.ok) return null;
  return normalizeESPNDetail(await response.json());
}
async function apiMatchDetail(match) {
  const id=match?.providerIds?.apiFootball; if(!id) return null;
  const [events,statistics,lineups]=await Promise.allSettled([
    apiFootballJSON('fixtures/events',{fixture:id}),apiFootballJSON('fixtures/statistics',{fixture:id}),apiFootballJSON('fixtures/lineups',{fixture:id})
  ]);
  return {
    events:events.status==='fulfilled'?(events.value.response||[]):[],
    statistics:statistics.status==='fulfilled'?(statistics.value.response||[]):[],
    lineups:lineups.status==='fulfilled'?(lineups.value.response||[]):[],source:'api-football'
  };
}
function mergeMatchDetails(api,espn) {
  return {
    events:(api?.events?.length?api.events:espn?.events)||[],
    statistics:(api?.statistics?.length?api.statistics:espn?.statistics)||[],
    lineups:(api?.lineups?.length?api.lineups:espn?.lineups)||[],
    venue:espn?.venue || null,officials:espn?.officials || [],
    coverage:{events:api?.events?.length?'api-football':(espn?.events?.length?'espn':null),statistics:api?.statistics?.length?'api-football':(espn?.statistics?.length?'espn':null),lineups:api?.lineups?.length?'api-football':(espn?.lineups?.length?'espn':null)}
  };
}
async function canonicalMatchDetail(id) {
  let match=canonicalMatchIndex.get(id);
  if (!match) throw Object.assign(new Error('match_not_indexed'),{status:404});
  const cacheKey=`v2:match:${id}`; const cached=getCached(cacheKey); if(cached) return JSON.parse(cached.body);
  const espnPromise=espnMatchDetail(match).catch(()=>null);
  let api=null; try { api=await apiMatchDetail(match); } catch { api=null; }
  const espn=await espnPromise;
  const detail={match,...mergeMatchDetails(api,espn),generatedAt:new Date().toISOString()};
  putCache(cacheKey,{status:200,ok:true,body:JSON.stringify(detail)},20);
  return detail;
}

function decodeXML(text='') { return text.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g,'$1').replace(/&amp;/g,'&').replace(/&quot;/g,'"').replace(/&#39;/g,"'").replace(/&lt;/g,'<').replace(/&gt;/g,'>'); }
function tag(block,name) { const m=block.match(new RegExp(`<${name}[^>]*>([\\s\\S]*?)<\\/${name}>`,'i')); return m?decodeXML(m[1].trim()):null; }
async function transfermarktReferences(query='football transfers') {
  const q=String(query||'football transfers').trim().slice(0,80);
  const searchURL=`https://www.transfermarkt.com/schnellsuche/ergebnis/schnellsuche?query=${encodeURIComponent(q)}`;
  const rss=`https://news.google.com/rss/search?q=${encodeURIComponent(`site:transfermarkt.com ${q}`)}&hl=en&gl=US&ceid=US:en`;
  try {
    const response=await fetchWithTimeout(rss,{headers:{'user-agent':'NinetyPlus-Backend/0.7'}},10000);
    if(!response.ok) throw new Error('rss_failed');
    const xml=await response.text(); const blocks=[...xml.matchAll(/<item>([\s\S]*?)<\/item>/gi)].map(m=>m[1]).slice(0,20);
    const items=blocks.map(b=>({title:tag(b,'title'),url:tag(b,'link'),publishedAt:tag(b,'pubDate'),source:'Transfermarkt via Google News'})).filter(x=>x.title&&x.url);
    return {query:q,searchURL,items,notice:'Transfermarkt is used as an external reference. 90+ does not scrape protected pages or claim unverified market values.'};
  } catch {
    return {query:q,searchURL,items:[],notice:'Transfermarkt reference search is available; indexed headlines are temporarily unavailable.'};
  }
}

const server = http.createServer(async (req,res) => {
  if (!req.url) return sendJson(res,400,{error:'bad_request'});
  const url = new URL(req.url,`http://${req.headers.host || 'localhost'}`);
  if (req.method === 'OPTIONS') { res.writeHead(204,{'Access-Control-Allow-Origin':'*','Access-Control-Allow-Methods':'GET, OPTIONS','Access-Control-Allow-Headers':'Content-Type, Accept'}); return res.end(); }
  if (req.method !== 'GET') return sendJson(res,405,{error:'method_not_allowed'},{Allow:'GET'});
  if (url.pathname === '/' || url.pathname === '/api/health') {
    const configured = Boolean(process.env.API_FOOTBALL_KEY); resetProviderBudgetIfNeeded();
    return sendJson(res,200,{ok:true,service:'ninetyplus-backend',version:'0.7',platform:'railway',providerConfigured:configured,canonicalDataEngine:true,espnFallback:true,transfermarktReferences:true,cacheEntries:responseCache.size,indexedMatches:canonicalMatchIndex.size,inFlightRequests:inFlight.size,providerRequestsToday,providerDailyBudget:PROVIDER_DAILY_BUDGET,time:new Date().toISOString()},{'Cache-Control':'no-store'});
  }
  if (!allowClient(req)) return sendJson(res,429,{error:'rate_limited'},{'Cache-Control':'no-store','Retry-After':'60'});
  if (url.pathname === '/api/football') return handleFootball(req,res,url);
  if (url.pathname === '/api/v2/fixtures') {
    const date=String(url.searchParams.get('date')||'');
    if(!/^\d{4}-\d{2}-\d{2}$/.test(date)) return sendJson(res,400,{error:'invalid_date'});
    try { return sendJson(res,200,await canonicalFixtures(date),{'Cache-Control':'public, max-age=30, stale-while-revalidate=120','X-90Plus-Source':'canonical'}); }
    catch(error) { return sendJson(res,503,{error:'fixtures_unavailable',message:error?.message}); }
  }
  if (url.pathname === '/api/v2/match') {
    const id=String(url.searchParams.get('id')||''); if(!id.startsWith('np:')) return sendJson(res,400,{error:'invalid_match_id'});
    try { return sendJson(res,200,await canonicalMatchDetail(id),{'Cache-Control':'public, max-age=15, stale-while-revalidate=60','X-90Plus-Source':'canonical'}); }
    catch(error) { return sendJson(res,error?.status||503,{error:error?.message||'match_unavailable'}); }
  }
  if (url.pathname === '/api/v2/transfers') {
    return sendJson(res,200,await transfermarktReferences(url.searchParams.get('q')||'football transfers'),{'Cache-Control':'public, max-age=300'});
  }
  return sendJson(res,404,{error:'not_found'},{'Cache-Control':'no-store'});
});

setInterval(()=>{
  const cutoff = Date.now()-5*60_000;
  for (const [key,value] of clientWindows) if (value.startedAt < cutoff) clientWindows.delete(key);
  if (canonicalMatchIndex.size > 5000) canonicalMatchIndex.clear();
},60_000).unref();

server.listen(PORT,'0.0.0.0',()=>console.log(`90+ backend v0.7 listening on ${PORT}`));
