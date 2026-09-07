import http from 'node:http';
import { randomUUID } from 'node:crypto';

const API_BASE = 'https://v3.football.api-sports.io';
const PORT = Number(process.env.PORT || 3000);
const CACHE_LIMIT = 500;
const RESPONSE_RATE_LIMIT = Number(process.env.RESPONSE_RATE_LIMIT || 120);
const PROVIDER_DAILY_BUDGET = Number(process.env.PROVIDER_DAILY_BUDGET || 90);
const responseCache = new Map();
const inFlight = new Map();
const clientWindows = new Map();
let providerBudgetDay = new Date().toISOString().slice(0, 10);
let providerRequestsToday = 0;

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

function sendJson(res, status, payload, extraHeaders = {}) {
  const body = JSON.stringify(payload);
  sendBody(res, status, body, extraHeaders);
}

function sendBody(res, status, body, extraHeaders = {}) {
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

function clientAddress(req) {
  const forwarded = String(req.headers['x-forwarded-for'] || '').split(',')[0].trim();
  return forwarded || req.socket.remoteAddress || 'unknown';
}

function allowClient(req) {
  const now = Date.now();
  const key = clientAddress(req);
  const current = clientWindows.get(key);
  if (!current || now - current.startedAt >= 60_000) {
    clientWindows.set(key, { startedAt: now, count: 1 });
    return true;
  }
  current.count += 1;
  return current.count <= RESPONSE_RATE_LIMIT;
}

function resetProviderBudgetIfNeeded() {
  const today = new Date().toISOString().slice(0, 10);
  if (today !== providerBudgetDay) {
    providerBudgetDay = today;
    providerRequestsToday = 0;
  }
}

function providerBudgetAvailable() {
  resetProviderBudgetIfNeeded();
  return providerRequestsToday < PROVIDER_DAILY_BUDGET;
}

function noteProviderRequest() {
  resetProviderBudgetIfNeeded();
  providerRequestsToday += 1;
}

function normalizeRequest(url) {
  const path = String(url.searchParams.get('path') || '').replace(/^\/+/, '');
  if (!ALLOWED_PATHS.has(path)) return { error: 'unsupported_path' };

  const upstream = new URL(`${API_BASE}/${path}`);
  const safeQuery = {};
  for (const [name, value] of url.searchParams.entries()) {
    if (name === 'path' || !ALLOWED_QUERY_KEYS.has(name)) continue;
    const text = String(value).trim();
    if (!text || text.length > 120) continue;
    upstream.searchParams.set(name, text);
    safeQuery[name] = text;
  }

  upstream.searchParams.sort();
  return {
    path,
    safeQuery,
    upstream,
    cacheKey: `${path}?${upstream.searchParams.toString()}`
  };
}

function getCached(cacheKey) {
  const entry = responseCache.get(cacheKey);
  if (!entry) return null;
  if (entry.expiresAt <= Date.now()) return null;
  entry.lastAccess = Date.now();
  return entry;
}

function getStale(cacheKey) {
  const entry = responseCache.get(cacheKey);
  if (!entry) return null;
  const maxStaleMs = Math.max(entry.ttl * 3, 60) * 1000;
  if (Date.now() - entry.expiresAt > maxStaleMs) return null;
  return entry;
}

function putCache(cacheKey, result, ttl) {
  if (responseCache.size >= CACHE_LIMIT && !responseCache.has(cacheKey)) {
    const oldest = [...responseCache.entries()].sort((a, b) => a[1].lastAccess - b[1].lastAccess)[0];
    if (oldest) responseCache.delete(oldest[0]);
  }
  responseCache.set(cacheKey, {
    ...result,
    ttl,
    expiresAt: Date.now() + ttl * 1000,
    lastAccess: Date.now()
  });
}

async function fetchProvider(upstream, key, requestId) {
  if (!providerBudgetAvailable()) {
    const error = new Error('provider_daily_budget_exhausted');
    error.budgetExhausted = true;
    throw error;
  }

  noteProviderRequest();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 12000);
  try {
    const response = await fetch(upstream, {
      signal: controller.signal,
      headers: {
        'x-apisports-key': key,
        accept: 'application/json',
        'user-agent': 'NinetyPlus-Backend/0.5 Railway'
      }
    });
    const body = await response.text();
    return {
      status: response.status,
      ok: response.ok,
      body,
      remaining: response.headers.get('x-ratelimit-requests-remaining')
    };
  } catch (error) {
    const timedOut = error?.name === 'AbortError';
    console.error('football provider failed', { requestId, timedOut, message: error?.message });
    throw Object.assign(error, { timedOut });
  } finally {
    clearTimeout(timeout);
  }
}

async function handleFootball(req, res, url) {
  const requestId = randomUUID();
  const key = process.env.API_FOOTBALL_KEY;
  if (!key) return sendJson(res, 503, { error: 'sports_provider_not_configured', requestId }, { 'Cache-Control': 'no-store' });

  const normalized = normalizeRequest(url);
  if (normalized.error) return sendJson(res, 400, { error: normalized.error, requestId }, { 'Cache-Control': 'no-store' });

  const { path, safeQuery, upstream, cacheKey } = normalized;
  const ttl = cacheSeconds(path, safeQuery);
  const cached = getCached(cacheKey);

  if (cached) {
    return sendBody(res, cached.status, cached.body, {
      'Cache-Control': `public, max-age=${ttl}, stale-while-revalidate=${Math.max(ttl * 3, 60)}`,
      'X-90Plus-Request-ID': requestId,
      'X-90Plus-Source': 'api-football',
      'X-90Plus-Cache': 'HIT'
    });
  }

  try {
    let promise = inFlight.get(cacheKey);
    if (!promise) {
      promise = fetchProvider(upstream, key, requestId);
      inFlight.set(cacheKey, promise);
    }

    const result = await promise;
    inFlight.delete(cacheKey);

    if (result.ok) putCache(cacheKey, result, ttl);

    const headers = {
      'Cache-Control': result.ok ? `public, max-age=${ttl}, stale-while-revalidate=${Math.max(ttl * 3, 60)}` : 'no-store',
      'X-90Plus-Request-ID': requestId,
      'X-90Plus-Source': 'api-football',
      'X-90Plus-Cache': 'MISS'
    };
    if (result.remaining) headers['X-90Plus-Provider-Remaining'] = result.remaining;

    return sendBody(res, result.status, result.body, headers);
  } catch (error) {
    inFlight.delete(cacheKey);
    const stale = getStale(cacheKey);
    if (stale) {
      return sendBody(res, stale.status, stale.body, {
        'Cache-Control': 'no-store',
        'X-90Plus-Request-ID': requestId,
        'X-90Plus-Source': 'api-football',
        'X-90Plus-Cache': 'STALE'
      });
    }

    if (error?.budgetExhausted) {
      return sendJson(res, 429, {
        error: 'provider_daily_budget_exhausted',
        requestId
      }, { 'Cache-Control': 'no-store', 'Retry-After': '3600', 'X-90Plus-Request-ID': requestId });
    }

    return sendJson(res, error?.timedOut ? 504 : 502, {
      error: error?.timedOut ? 'sports_provider_timeout' : 'sports_provider_unavailable',
      requestId
    }, { 'Cache-Control': 'no-store', 'X-90Plus-Request-ID': requestId });
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
    resetProviderBudgetIfNeeded();
    return sendJson(res, configured ? 200 : 503, {
      ok: configured,
      service: 'ninetyplus-backend',
      version: '0.5',
      platform: 'railway',
      providerConfigured: configured,
      cacheEntries: responseCache.size,
      inFlightRequests: inFlight.size,
      providerRequestsToday,
      providerDailyBudget: PROVIDER_DAILY_BUDGET,
      time: new Date().toISOString()
    }, { 'Cache-Control': 'no-store' });
  }

  if (!allowClient(req)) {
    return sendJson(res, 429, { error: 'rate_limited' }, {
      'Cache-Control': 'no-store',
      'Retry-After': '60'
    });
  }

  if (url.pathname === '/api/football') return handleFootball(req, res, url);

  return sendJson(res, 404, { error: 'not_found' }, { 'Cache-Control': 'no-store' });
});

setInterval(() => {
  const cutoff = Date.now() - 5 * 60_000;
  for (const [key, value] of clientWindows) {
    if (value.startedAt < cutoff) clientWindows.delete(key);
  }
}, 60_000).unref();

server.listen(PORT, '0.0.0.0', () => {
  console.log(`90+ backend listening on ${PORT}`);
});
