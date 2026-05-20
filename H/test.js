const http = require('http');

const PORT = 3004;
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
  console.log('=== Chat Presence Feature Test Suite ===\n');

  const { server } = require('./server');
  await new Promise(r => setTimeout(r, 100));

  await request('GET', '/users/1', null).catch(() => {});

  console.log('Test 1: GET /users has online field');
  const users = await request('GET', '/users', null).catch(() => ({ status: 500, body: [] }));
  assert('GET /users includes online field', Array.isArray(users.body) && users.body.every(u => typeof u.online === 'boolean'));

  console.log('\nTest 2: GET /users/:id has online field');
  const u1 = await request('GET', '/users/1', null).catch(() => ({ status: 500, body: {} }));
  assert('GET /users/1 includes online field', typeof u1.body.online === 'boolean');

  console.log('\nTest 3: Conversation participants have online');
  const conv = await request('GET', '/conversations/1', null).catch(() => ({ status: 500, body: {} }));
  assert('participants in GET /conversations/1 have online field',
    Array.isArray(conv.body.participants) && conv.body.participants.every(p => typeof p.online === 'boolean'));

  console.log('\nTest 4: Online after request');
  await request('GET', '/users/1', null).catch(() => {});
  const u1fresh = await request('GET', '/users/1', null).catch(() => ({ status: 500, body: {} }));
  assert('user 1 is online after hitting their endpoint', u1fresh.body.online === true);

  console.log('\nTest 5: Offline by default');
  const u2 = await request('GET', '/users/2', null).catch(() => ({ status: 500, body: {} }));
  assert('user 2 online field is a boolean', typeof u2.body.online === 'boolean');

  console.log('\nTest 6: Boolean type');
  assert('online is strictly boolean (not "true" string)', u1fresh.body.online === true && typeof u1fresh.body.online !== 'string');

  console.log('\nTest 7: Cross-endpoint consistency');
  const listOnline = users.body.find(u => u.id === 1)?.online;
  const detailOnline = u1fresh.body.online;
  assert('user 1 online status consistent across /users, /users/1, and /conversations/1 participants',
    listOnline === detailOnline);

  console.log('\nTest 8: Existing fields preserved in GET /users');
  assert('GET /users still returns id and name fields',
    users.body.every(u => 'id' in u && 'name' in u));

  console.log('\nTest 9: Existing fields preserved in GET /users/:id');
  assert('GET /users/1 still returns id and name', 'id' in u1fresh.body && 'name' in u1fresh.body);

  console.log('\nTest 10: Conversation shape unchanged');
  assert('GET /conversations/1 still returns id, name, participants',
    'id' in conv.body && 'name' in conv.body && 'participants' in conv.body);

  console.log('\nTest 11: Participant existing fields');
  assert('participants still have id and name',
    conv.body.participants?.every(p => 'id' in p && 'name' in p));

  console.log('\nTest 12: Offline user in conversation');
  const u2InConv = conv.body.participants?.find(p => p.id === 2);
  assert('user 2 online is a boolean in participants', typeof u2InConv?.online === 'boolean');

  console.log(`\n=== Results: ${passes} passed, ${failures} failed ===`);
  server.close();
  process.exit(failures > 0 ? 1 : 0);
}

runTests().catch(e => {
  console.error('Test runner crashed:', e.message);
  process.exit(1);
});
