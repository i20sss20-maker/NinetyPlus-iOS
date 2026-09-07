import http from 'node:http';

const EXTERNAL_PORT = Number(process.env.PORT || 3000);
const INNER_PORT = EXTERNAL_PORT === 18080 ? 18081 : 18080;
const INNER_BASE = `http://127.0.0.1:${INNER_PORT}`;

// Run the proven v0.7 engine privately, then put the v0.8 compatibility layer
// in front of it. This keeps the mature provider/cache logic untouched while
// making canonical match IDs recoverable after a Railway restart.
process.env.PORT = String(INNER_PORT);
await import('./server.js');
process.env.PORT = String(EXTERNAL_PORT);

function sendJson(res, status, payload, headers = {}) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'X-Content-Type-Options': 'nosniff',
    'Access-Control-Allow-Origin': '*',
    ...headers
  });
  res.end(body);
}

function encodedID(date, legacyID) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(date || ''))) return legacyID;
  const match = String(legacyID || '').match(/^np:([a-f0-9]{16})$/i);
  return match ? `np:${date}:${match[1]}` : legacyID;
}

function decodeID(value) {
  const text = String(value || '');
  const modern = text.match(/^np:(\d{4}-\d{2}-\d{2}):([a-f0-9]{16})$/i);
  if (modern) return { date: modern[1], legacyID: `np:${modern[2]}` };
  const legacy = text.match(/^np:([a-f0-9]{16})$/i);
  if (legacy) return { date: null, legacyID: text };
  return null;
}

async function inner(pathname, search = '') {
  const response = await fetch(`${INNER_BASE}${pathname}${search}`, {
    headers: { accept: 'application/json', 'user-agent': 'NinetyPlus-Backend/0.8' }
  });
  const text = await response.text();
  let json = null;
  try { json = JSON.parse(text); } catch {}
  return { response, text, json };
}

function copyHeaders(response, extra = {}) {
  const headers = {
    'Cache-Control': response.headers.get('cache-control') || 'no-store',
    'X-90Plus-Source': response.headers.get('x-90plus-source') || 'canonical-v08',
    ...extra
  };
  const retry = response.headers.get('retry-after');
  if (retry) headers['Retry-After'] = retry;
  return headers;
}

async function fixtures(res, url) {
  const date = String(url.searchParams.get('date') || '');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return sendJson(res, 400, { error: 'invalid_date' });
  const result = await inner('/api/v2/fixtures', `?date=${encodeURIComponent(date)}`);
  if (!result.response.ok || !result.json) {
    return sendJson(res, result.response.status, result.json || { error: 'fixtures_unavailable' }, copyHeaders(result.response));
  }
  const payload = result.json;
  payload.matches = (payload.matches || []).map(match => ({
    ...match,
    canonicalId: encodedID(date, match.canonicalId),
    legacyCanonicalId: match.canonicalId
  }));
  payload.meta = { ...(payload.meta || {}), recoverableCanonicalIDs: true, engineVersion: '0.8' };
  return sendJson(res, 200, payload, copyHeaders(result.response, { 'X-90Plus-Engine': '0.8' }));
}

async function matchDetail(res, url) {
  const decoded = decodeID(url.searchParams.get('id'));
  if (!decoded) return sendJson(res, 400, { error: 'invalid_match_id' });

  // A modern ID contains its fixture day. Re-fetching that single day restores
  // v0.7's in-memory index after process restarts, deploys or cache eviction.
  if (decoded.date) {
    const indexed = await inner('/api/v2/fixtures', `?date=${encodeURIComponent(decoded.date)}`);
    if (!indexed.response.ok) {
      return sendJson(res, indexed.response.status, indexed.json || { error: 'match_day_unavailable' }, copyHeaders(indexed.response));
    }
  }

  const result = await inner('/api/v2/match', `?id=${encodeURIComponent(decoded.legacyID)}`);
  if (!result.response.ok || !result.json) {
    return sendJson(res, result.response.status, result.json || { error: 'match_unavailable' }, copyHeaders(result.response));
  }
  const payload = result.json;
  if (payload.match) {
    payload.match = {
      ...payload.match,
      canonicalId: encodedID(decoded.date || String(payload.match.dateUTC || '').slice(0, 10), payload.match.canonicalId),
      legacyCanonicalId: payload.match.canonicalId
    };
  }
  payload.engineVersion = '0.8';
  payload.recoveredFromDate = decoded.date || null;
  return sendJson(res, 200, payload, copyHeaders(result.response, { 'X-90Plus-Engine': '0.8' }));
}

async function passthrough(req, res, url) {
  const result = await inner(url.pathname, url.search);
  if (url.pathname === '/' || url.pathname === '/api/health') {
    const payload = result.json || {};
    return sendJson(res, result.response.ok ? 200 : result.response.status, {
      ...payload,
      ok: result.response.ok,
      version: '0.8',
      recoverableCanonicalIDs: true,
      matchDayReindex: true
    }, copyHeaders(result.response, { 'X-90Plus-Engine': '0.8' }));
  }
  if (result.json) return sendJson(res, result.response.status, result.json, copyHeaders(result.response));
  res.writeHead(result.response.status, { 'Content-Type': result.response.headers.get('content-type') || 'text/plain; charset=utf-8' });
  res.end(result.text);
}

const server = http.createServer(async (req, res) => {
  try {
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
    if (url.pathname === '/api/v2/fixtures') return await fixtures(res, url);
    if (url.pathname === '/api/v2/match') return await matchDetail(res, url);
    return await passthrough(req, res, url);
  } catch (error) {
    console.error('v0.8 proxy error', { message: error?.message, stack: error?.stack });
    return sendJson(res, 502, { error: 'data_engine_unavailable' });
  }
});

server.listen(EXTERNAL_PORT, '0.0.0.0', () => console.log(`90+ data engine v0.8 listening on ${EXTERNAL_PORT} -> ${INNER_PORT}`));
