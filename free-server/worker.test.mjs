import test from 'node:test';
import assert from 'node:assert/strict';
import {upstreamFor} from './worker.mjs';
test('routes only documented free sources', () => {
  const url = upstreamFor(new URL('https://test/free/espn/ksa.1/scoreboard?dates=20260910&url=https://evil.test'));
  assert.equal(url.href, 'https://site.web.api.espn.com/apis/site/v2/sports/soccer/ksa.1/scoreboard?dates=20260910');
  assert.equal(upstreamFor(new URL('https://test/free/espn/ksa.1/standings')).pathname, '/apis/v2/sports/soccer/ksa.1/standings');
  assert.equal(upstreamFor(new URL('https://test/free/directory/searchplayers.php?p=Lionel%20Messi')).searchParams.get('p'), 'Lionel Messi');
});
test('rejects arbitrary upstream paths and identifiers', () => {
  for (const path of ['/free/espn/evil/teams','/free/espn/ksa.1/admin','/free/directory/lookupplayer.php?id=tsdb:12','/free/directory/secret','/proxy?url=http://localhost']) {
    assert.throws(() => upstreamFor(new URL('https://test' + path)));
  }
});
