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
  if (path.startsWith('fixtures/')) return 20;
  if (path === 'fixtures' && query.date) return 30;
  if (path === 'standings') return 300;
  if (path === 'players/topscorers') return 300;
  if (path === 'players' || path === 'players/profiles') return 900;
  if (path === 'teams') return 3600;
  return 60;
}

export default async function handler(req, res) {
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    return res.status(405).json({ error: 'method_not_allowed' });
  }

  const key = process.env.API_FOOTBALL_KEY;
  if (!key) return res.status(503).json({ error: 'sports_provider_not_configured' });

  const path = String(req.query.path || '').replace(/^\/+/, '');
  if (!ALLOWED_PATHS.has(path)) return res.status(400).json({ error: 'unsupported_path' });

  const upstream = new URL(`${API_BASE}/${path}`);
  const safeQuery = {};
  for (const [name, rawValue] of Object.entries(req.query)) {
    if (name === 'path' || !ALLOWED_QUERY_KEYS.has(name)) continue;
    const value = Array.isArray(rawValue) ? rawValue[0] : rawValue;
    if (value === undefined || value === null || String(value).length > 120) continue;
    upstream.searchParams.set(name, String(value));
    safeQuery[name] = String(value);
  }

  try {
    const response = await fetch(upstream, {
      headers: {
        'x-apisports-key': key,
        'accept': 'application/json',
        'user-agent': 'NinetyPlus-Backend/0.1'
      }
    });

    const body = await response.text();
    const ttl = cacheSeconds(path, safeQuery);

    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.setHeader('Cache-Control', `public, s-maxage=${ttl}, stale-while-revalidate=${Math.max(ttl, 60)}`);
    res.setHeader('X-90Plus-Source', 'api-football');
    return res.status(response.status).send(body);
  } catch (error) {
    console.error('football proxy failed', error);
    return res.status(502).json({ error: 'sports_provider_unavailable' });
  }
}
