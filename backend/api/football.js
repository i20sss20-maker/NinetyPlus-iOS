const API_BASE = 'https://v3.football.api-sports.io';

const ALLOWED_PATHS = new Set([
  'fixtures',
  'standings',
  'teams',
  'players/profiles',
  'players/topscorers',
  'players',
  'fixtures/events',
  'fixtures/statistics',
  'fixtures/lineups',
  'fixtures/headtohead'
]);

const ALLOWED_QUERY_KEYS = new Set([
  'id', 'date', 'timezone', 'live', 'league', 'season', 'last', 'next',
  'team', 'search', 'player', 'fixture', 'h2h', 'page'
]);

function cacheSeconds(path, query) {
  if (path === 'fixtures' && query.live) return 15;
  if (path === 'fixtures/events') return 15;
  if (path === 'fixtures/statistics' || path === 'fixtures/lineups') return 30;
  if (path === 'fixtures/headtohead') return 900;
  if (path === 'fixtures' && query.date) return 45;
  if (path === 'standings') return 300;
  if (path === 'players/topscorers') return 300;
  if (path === 'players' || path === 'players/profiles') return 900;
  if (path === 'teams') return 3600;
  return 60;
}

function applyCommonHeaders(res, requestId) {
  res.setHeader('X-90Plus-Request-ID', requestId);
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('Access-Control-Allow-Origin', '*');
}

export default async function handler(req, res) {
  const requestId = globalThis.crypto?.randomUUID?.() || `${Date.now()}-${Math.random().toString(36).slice(2)}`;
  applyCommonHeaders(res, requestId);

  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    return res.status(405).json({ error: 'method_not_allowed', requestId });
  }

  const key = process.env.API_FOOTBALL_KEY;
  if (!key) return res.status(503).json({ error: 'sports_provider_not_configured', requestId });

  const path = String(req.query.path || '').replace(/^\/+/, '');
  if (!ALLOWED_PATHS.has(path)) return res.status(400).json({ error: 'unsupported_path', requestId });

  const upstream = new URL(`${API_BASE}/${path}`);
  const safeQuery = {};
  for (const [name, rawValue] of Object.entries(req.query)) {
    if (name === 'path' || !ALLOWED_QUERY_KEYS.has(name)) continue;
    const value = Array.isArray(rawValue) ? rawValue[0] : rawValue;
    if (value === undefined || value === null) continue;
    const text = String(value).trim();
    if (!text || text.length > 120) continue;
    upstream.searchParams.set(name, text);
    safeQuery[name] = text;
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 12000);

  try {
    const response = await fetch(upstream, {
      signal: controller.signal,
      headers: {
        'x-apisports-key': key,
        'accept': 'application/json',
        'user-agent': 'NinetyPlus-Backend/0.2'
      }
    });

    const body = await response.text();
    const ttl = cacheSeconds(path, safeQuery);

    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.setHeader('X-90Plus-Source', 'api-football');

    const remaining = response.headers.get('x-ratelimit-requests-remaining');
    if (remaining) res.setHeader('X-90Plus-Provider-Remaining', remaining);

    if (response.ok) {
      res.setHeader('Cache-Control', `public, s-maxage=${ttl}, stale-while-revalidate=${Math.max(ttl * 3, 60)}`);
    } else {
      res.setHeader('Cache-Control', 'no-store');
    }

    return res.status(response.status).send(body);
  } catch (error) {
    const timedOut = error?.name === 'AbortError';
    console.error('football proxy failed', { requestId, path, timedOut, message: error?.message });
    res.setHeader('Cache-Control', 'no-store');
    return res.status(timedOut ? 504 : 502).json({
      error: timedOut ? 'sports_provider_timeout' : 'sports_provider_unavailable',
      requestId
    });
  } finally {
    clearTimeout(timeout);
  }
}
