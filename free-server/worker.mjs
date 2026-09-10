// Curated public-source gateway. No paid provider keys or arbitrary URL proxying.
const leagues = new Set(['ksa.1','eng.1','esp.1','ita.1','ger.1','fra.1','uefa.champions']);
const directory = new Set(['searchplayers.php','lookupplayer.php']);
export function upstreamFor(url) {
  const parts = url.pathname.split('/').filter(Boolean);
  if (parts[0] !== 'free') throw new Error('unsupported_route');
  let upstream;
  if (parts[1] === 'espn' && leagues.has(parts[2])) {
    let route = parts.slice(3).join('/');
    if (!['scoreboard','teams','summary','standings'].includes(route) && !/^teams\/\d+\/schedule$/.test(route)) throw new Error('unsupported_route');
    const version = route === 'standings' ? 'v2' : 'site/v2';
    upstream = new URL(`https://site.web.api.espn.com/apis/${version}/sports/soccer/${parts[2]}/${route}`);
    for (const key of ['dates','event','limit','season']) {
      const value = url.searchParams.get(key);
      if (value && /^[0-9-]{1,20}$/.test(value)) upstream.searchParams.set(key, value);
    }
  } else if (parts[1] === 'directory' && parts.length === 3 && directory.has(parts[2])) {
    upstream = new URL(`https://www.thesportsdb.com/api/v1/json/123/${parts[2]}`);
    const key = parts[2] === 'searchplayers.php' ? 'p' : 'id';
    const value = url.searchParams.get(key)?.trim();
    if (!value || value.length > 80 || (key === 'id' && !/^\d+$/.test(value))) throw new Error('invalid_query');
    upstream.searchParams.set(key, value);
  } else throw new Error('unsupported_route');
  return upstream;
}
const json = (value, status = 200) => new Response(JSON.stringify(value), { status, headers: {'Content-Type':'application/json','Access-Control-Allow-Origin':'*'} });
export default {
  async fetch(request, env, ctx) {
    if (request.method !== 'GET') return json({error:'method_not_allowed'}, 405);
    const url = new URL(request.url);
    if (url.pathname === '/api/health') return json({ok:true,service:'90plus-free',version:'1.0',sources:['ESPN','TheSportsDB'],paidProviderEnabled:false});
    let upstream;
    try { upstream = upstreamFor(url); } catch (e) { return json({error:e.message}, 400); }
    // The free directory rejects requests from some shared datacenter IPs.
    // Let the app access its public endpoint directly, under its own free quota.
    if (upstream.hostname === 'www.thesportsdb.com') {
      return new Response(null, {status:307,headers:{'Location':upstream.href,'Cache-Control':'no-store','Access-Control-Allow-Origin':'*'}});
    }
    const key = new Request(new URL('/cached/' + encodeURIComponent(upstream.href), url.origin));
    const cache = caches.default;
    const cached = await cache.match(key);
    if (cached) return cached;
    try {
      const response = await fetch(upstream, { headers: {'Accept':'application/json'}, signal: AbortSignal.timeout(12000) });
      if (!response.ok) return json({error:'source_unavailable',upstreamStatus:response.status}, 503);
      const data = await response.json();
      const ttl = url.pathname.includes('/directory/') || url.pathname.endsWith('/teams') ? 3600 : 60;
      const result = json(data);
      result.headers.set('Cache-Control', `public, max-age=${ttl}`);
      result.headers.set('X-90Plus-Source', upstream.hostname.includes('espn') ? 'ESPN' : 'TheSportsDB');
      ctx.waitUntil(cache.put(key, result.clone()));
      return result;
    } catch { return json({error:'source_unavailable'}, 503); }
  }
};
