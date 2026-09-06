import http from 'node:http';
import { randomUUID } from 'node:crypto';

const API_BASE = 'https://v3.football.api-sports.io';
const PORT = Number(process.env.PORT || 3000);

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

function sendJson(res, status, payload, extraHeaders = {}) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'no-referrer',
    'Access-Control-Allow-Origin': '*',
    ...extraHeaders
  });
  res.end(body);
}

async function handleFootball(req, res, url) {
  const requestId = randomUUID();
  const key = process.env.API_FOOTBALL_KEY;
  if (!key) return sendJson(res, 503, { error: 'sports_provider_not_configured', requestId }, { 'Cache-Control': 'no-store' });

  const path = String(url.searchParams.get('path') || '').replace(/^\/+/, '');
  if (!ALLOWED_PATHS.has(path)) return sendJson(res, 400, { error: 'unsupported_path', requestId }, { 'Cache-Control': 'no-store' });

  const upstream = new URL(`${API_BASE}/${path}`);
  const safeQuery = {};
  for (const [name, value] of url.searchParams.entries()) {
    if (name === 'path' || !ALLOWED_QUERY_KEYS.has(name)) continue;
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
        'user-agent': 'NinetyPlus-Backend/0.3 Railway'
      }
    });

    const body = await response.text();
    const ttl = cacheSeconds(path, safeQuery);
    const headers = {
      'Content-Type': 'application/json; charset=utf-8',
      'X-90Plus-Request-ID': requestId,
      'X-90Plus-Source': 'api-football',
      'X-Content-Type-Options': 'nosniff',
      'Referrer-Policy': 'no-referrer',
      'Access-Control-Allow-Origin': '*',
      'Cache-Control': response.ok ? `public, max-age=${ttl}, stale-while-revalidate=${Math.max(ttl * 3, 60)}` : 'no-store'
    };
    const remaining = response.headers.get('x-ratelimit-requests-remaining');
    if (remaining) headers['X-90Plus-Provider-Remaining'] = remaining;

    res.writeHead(response.status, headers);
    res.end(body);
  } catch (error) {
    const timedOut = error?.name === 'AbortError';
    console.error('football proxy failed', { requestId, path, timedOut, message: error?.message });
    sendJson(res, timedOut ? 504 : 502, {
      error: timedOut ? 'sports_provider_timeout' : 'sports_provider_unavailable',
      requestId
    }, { 'Cache-Control': 'no-store', 'X-90Plus-Request-ID': requestId });
  } finally {
    clearTimeout(timeout);
  }
}

const server = http.createServer(async (req, res) => {
  if (!req.url) return sendJson(res, 400, { error: 'bad_request' });
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);

  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Accept'
    });
    return res.end();
  }

  if (req.method !== 'GET') return sendJson(res, 405, { error: 'method_not_allowed' }, { Allow: 'GET' });

  if (url.pathname === '/' || url.pathname === '/api/health') {
    const configured = Boolean(process.env.API_FOOTBALL_KEY);
    return sendJson(res, configured ? 200 : 503, {
      ok: configured,
      service: 'ninetyplus-backend',
      version: '0.3',
      platform: 'railway',
      providerConfigured: configured,
      time: new Date().toISOString()
    }, { 'Cache-Control': 'no-store' });
  }

  if (url.pathname === '/api/football') return handleFootball(req, res, url);

  return sendJson(res, 404, { error: 'not_found' }, { 'Cache-Control': 'no-store' });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`90+ backend listening on ${PORT}`);
});
