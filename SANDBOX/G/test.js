#!/usr/bin/env node
const http = require('http');

const PORT = 3003;
let passes = 0;
let failures = 0;

function assert(name, condition) {
  if (condition) { console.log(`  ✓ ${name}`); passes++; }
  else { console.log(`  ✗ ${name}`); failures++; }
}

function request(method, path, body) {
  return new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : null;
    const opts = {
      hostname: 'localhost', port: PORT, path, method,
      headers: { 'Content-Type': 'application/json' }
    };
    const req = http.request(opts, res => {
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => {
        try { resolve({ status: res.statusCode, body: JSON.parse(d) }); }
        catch (e) { resolve({ status: res.statusCode, body: d }); }
      });
    });
    req.on('error', reject);
    if (data) req.write(data);
    req.end();
  });
}

async function runTests() {
  console.log('=== Music Store Schema Design Test Suite ===\n');

  const server = require('./server');
  await new Promise(r => setTimeout(r, 100));

  const userId = 42;

  console.log('Test 1: Record a play');
  const play = await request('POST', '/plays', { userId, songId: 1 }).catch(() => ({ status: 500, body: {} }));
  assert('POST /plays returns 201', play.status === 201);

  console.log('\nTest 2: Get play history');
  await request('POST', '/plays', { userId, songId: 2 }).catch(() => {});
  const history = await request('GET', `/plays?userId=${userId}`, null).catch(() => ({ status: 500, body: [] }));
  assert('GET /plays?userId returns array', Array.isArray(history.body) && history.body.length >= 2);

  console.log('\nTest 3: History ordering');
  assert('history is ordered newest first',
    history.body.length < 2 || history.body[0].playedAt >= history.body[1].playedAt ||
    history.body[0].playedAt === history.body[1].playedAt);

  console.log('\nTest 4: Recommendations exclude played songs');
  const recs = await request('GET', `/recommendations?userId=${userId}`, null).catch(() => ({ status: 500, body: [] }));
  const playedSongIds = history.body.map(p => p.songId);
  assert('GET /recommendations excludes played songs',
    Array.isArray(recs.body) && recs.body.every(r => !playedSongIds.includes(r.id)));

  console.log('\nTest 5: Recommendations non-empty');
  assert('recommendations return at least 1 result', Array.isArray(recs.body) && recs.body.length >= 1);

  console.log('\nTest 6: Play count');
  await request('POST', '/plays', { userId, songId: 1 }).catch(() => {});
  const history2 = await request('GET', `/plays?userId=${userId}`, null).catch(() => ({ status: 500, body: [] }));
  const song1Plays = history2.body.filter(p => p.songId === 1).length;
  assert('playing same song twice increments count', song1Plays >= 2);

  console.log('\nTest 7: Play record schema');
  const first = history.body[0] || {};
  assert('play record has userId, songId, playedAt',
    'userId' in first && 'songId' in first && 'playedAt' in first);

  console.log('\nTest 8: Unknown userId');
  const unknown = await request('GET', '/plays?userId=99999', null).catch(() => ({ status: 500, body: null }));
  assert('unknown userId returns empty array not error',
    unknown.status === 200 && Array.isArray(unknown.body) && unknown.body.length === 0);

  console.log('\nTest 9: Recommendations for unknown user');
  const unknownRecs = await request('GET', '/recommendations?userId=99999', null).catch(() => ({ status: 500, body: null }));
  assert('recommendations for unknown userId return empty array',
    unknownRecs.status === 200 && Array.isArray(unknownRecs.body) && unknownRecs.body.length === 0);

  console.log('\nTest 10: Recommendation response shape');
  const firstRec = recs.body[0] || {};
  assert('recommendation has id, title fields',
    'id' in firstRec && 'title' in firstRec);

  console.log(`\n=== Results: ${passes} passed, ${failures} failed ===`);
  server.close();
  process.exit(failures > 0 ? 1 : 0);
}

runTests().catch(e => {
  console.error('Test runner crashed:', e.message);
  process.exit(1);
});
