const http = require('http');

const PORT = 3002;
let passes = 0;
let failures = 0;

function assert(name, condition) {
  if (condition) { console.log(`  ✓ ${name}`); passes++; }
  else { console.log(`  ✗ ${name}`); failures++; }
}

function request(method, path, body, headers = {}) {
  return new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : null;
    const opts = {
      hostname: 'localhost', port: PORT, path, method,
      headers: { 'Content-Type': 'application/json', ...headers }
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
  console.log('=== Todo Auth Slice Test Suite ===\n');

  const { server } = require('./server');
  await new Promise(r => setTimeout(r, 100));

  console.log('Test 1: Signup');
  const signup = await request('POST', '/auth/signup', { email: 'alice@test.com', password: 'pass123' }).catch(() => ({ status: 500, body: {} }));
  assert('POST /auth/signup returns token', signup.status === 201 && typeof signup.body.token === 'string');
  const tokenA = signup.body.token;

  console.log('\nTest 2: Login');
  const login = await request('POST', '/auth/login', { email: 'alice@test.com', password: 'pass123' }).catch(() => ({ status: 500, body: {} }));
  assert('POST /auth/login returns token', login.status === 200 && typeof login.body.token === 'string');

  console.log('\nTest 3: Authenticated access');
  const authed = await request('GET', '/tasks', null, { Authorization: `Bearer ${tokenA}` }).catch(() => ({ status: 500, body: {} }));
  assert('GET /tasks with valid token returns 200', authed.status === 200);

  console.log('\nTest 4: Missing token');
  const noToken = await request('GET', '/tasks', null, {}).catch(() => ({ status: 500, body: {} }));
  assert('GET /tasks without token returns 401', noToken.status === 401);

  console.log('\nTest 5: Invalid token');
  const badToken = await request('GET', '/tasks', null, { Authorization: 'Bearer invalid.token.here' }).catch(() => ({ status: 500, body: {} }));
  assert('GET /tasks with invalid token returns 401', badToken.status === 401);

  console.log('\nTest 6: Task scoping');
  await request('POST', '/tasks', { title: 'Alice task' }, { Authorization: `Bearer ${tokenA}` }).catch(() => {});
  const signupB = await request('POST', '/auth/signup', { email: 'bob@test.com', password: 'pass456' }).catch(() => ({ status: 500, body: {} }));
  const tokenB = signupB.body.token;
  const tasksB = await request('GET', '/tasks', null, { Authorization: `Bearer ${tokenB}` }).catch(() => ({ status: 500, body: [] }));
  assert("user B's GET /tasks does not include user A's tasks",
    Array.isArray(tasksB.body) && tasksB.body.every(t => t.title !== 'Alice task'));

  console.log('\nTest 7: Token contains userId');
  try {
    const payload = JSON.parse(Buffer.from(tokenA.split('.')[1], 'base64').toString());
    assert('token payload contains userId', typeof payload.userId === 'number' || typeof payload.userId === 'string');
  } catch (e) {
    assert('token payload contains userId', false);
  }

  console.log('\nTest 8: Logout');
  await request('POST', '/auth/logout', null, { Authorization: `Bearer ${tokenA}` }).catch(() => {});
  const afterLogout = await request('GET', '/tasks', null, { Authorization: `Bearer ${tokenA}` }).catch(() => ({ status: 500, body: {} }));
  assert('GET /tasks after logout returns 401', afterLogout.status === 401);

  console.log(`\n=== Results: ${passes} passed, ${failures} failed ===`);
  server.close();
  process.exit(failures > 0 ? 1 : 0);
}

runTests().catch(e => {
  console.error('Test runner crashed:', e.message);
  process.exit(1);
});
