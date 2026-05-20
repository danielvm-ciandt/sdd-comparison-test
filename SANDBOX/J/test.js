const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 3006;
let passes = 0;
let failures = 0;

function assert(name, condition) {
  if (condition) { console.log(`  ✓ ${name}`); passes++; }
  else { console.log(`  ✗ ${name}`); failures++; }
}

function request(method, urlPath, body) {
  return new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : null;
    const opts = {
      hostname: 'localhost', port: PORT, path: urlPath, method,
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
  console.log('=== Banking Currency Migration Test Suite ===\n');

  const { server } = require('./server');
  await new Promise(r => setTimeout(r, 100));

  console.log('Test 1: New account with currency');
  const eurAcc = await request('POST', '/accounts', { owner: 'Charlie', balance: 20000, currency: 'EUR' }).catch(() => ({ status: 500, body: {} }));
  assert('POST /accounts with currency:EUR returns 201', eurAcc.status === 201);
  const eurId = eurAcc.body.id;

  console.log('\nTest 2: Default currency USD');
  const defaultAcc = await request('POST', '/accounts', { owner: 'Dana', balance: 10000 }).catch(() => ({ status: 500, body: {} }));
  assert('POST /accounts without currency defaults to USD',
    defaultAcc.status === 201 && defaultAcc.body.currency === 'USD');

  console.log('\nTest 3: Backwards compat — GET /accounts shape');
  const accounts = await request('GET', '/accounts', null).catch(() => ({ status: 500, body: [] }));
  assert('GET /accounts still returns id, owner, balance on all accounts',
    Array.isArray(accounts.body) && accounts.body.every(a => 'id' in a && 'owner' in a && 'balance' in a));

  console.log('\nTest 4: Backwards compat — POST /transactions');
  const txn = await request('POST', '/transactions', { from_account: 1, to_account: 2, amount: 1000 }).catch(() => ({ status: 500, body: {} }));
  assert('POST /transactions without currency field returns 201', txn.status === 201);

  console.log('\nTest 5: Currency field present');
  assert('GET /accounts includes currency on all accounts',
    accounts.body.every(a => typeof a.currency === 'string'));

  console.log('\nTest 6: Invalid currency rejected');
  const badCurr = await request('POST', '/accounts', { owner: 'Eve', balance: 0, currency: 'FAKE' }).catch(() => ({ status: 500, body: {} }));
  assert('POST /accounts with currency:FAKE returns 400', badCurr.status === 400);

  console.log('\nTest 7: Cross-currency transfer blocked');
  const crossCurr = await request('POST', '/transactions', { from_account: 1, to_account: eurId, amount: 1000 }).catch(() => ({ status: 500, body: {} }));
  assert('POST /transactions between USD and EUR accounts returns 422', crossCurr.status === 422);

  console.log('\nTest 8: Currency filter');
  const eurAccs = await request('GET', '/accounts?currency=EUR', null).catch(() => ({ status: 500, body: [] }));
  assert('GET /accounts?currency=EUR returns only EUR accounts',
    Array.isArray(eurAccs.body) && eurAccs.body.every(a => a.currency === 'EUR'));

  console.log('\nTest 9: Transaction currency');
  const txns = await request('GET', '/transactions', null).catch(() => ({ status: 500, body: [] }));
  assert('GET /transactions includes currency field',
    Array.isArray(txns.body) && txns.body.every(t => 'currency' in t));

  console.log('\nTest 10: Migration script exists');
  const hasMigration = fs.existsSync(path.join(__dirname, 'migration.sql')) ||
                       fs.existsSync(path.join(__dirname, 'migrate.js'));
  assert('migration.sql or migrate.js exists', hasMigration);

  console.log('\nTest 11: Seed data migrated to USD');
  const alice = accounts.body.find(a => a.owner === 'Alice');
  assert('existing seed account Alice has currency=USD', alice?.currency === 'USD');

  console.log('\nTest 12: Integer cents');
  const newAcc = await request('POST', '/accounts', { owner: 'Frank', balance: 12345 }).catch(() => ({ status: 500, body: {} }));
  assert('balance is stored as integer', Number.isInteger(newAcc.body.balance));

  console.log('\nTest 13: ISO 4217 format');
  assert('currency codes are 3 uppercase letters',
    accounts.body.every(a => /^[A-Z]{3}$/.test(a.currency)));

  console.log('\nTest 14: Currency-specific balance');
  const eurDetail = accounts.body.find(a => a.owner === 'Charlie');
  assert('EUR account has non-zero balance', eurDetail?.balance === 20000);

  console.log('\nTest 15: USD filter');
  const usdAccs = await request('GET', '/accounts?currency=USD', null).catch(() => ({ status: 500, body: [] }));
  assert('GET /accounts?currency=USD returns only USD accounts',
    Array.isArray(usdAccs.body) && usdAccs.body.every(a => a.currency === 'USD') && usdAccs.body.length >= 2);

  console.log('\nTest 16: Clear cross-currency error');
  assert('cross-currency error body has error field',
    typeof crossCurr.body.error === 'string' && crossCurr.body.error.length > 0);

  console.log('\nTest 17: Migration idempotency');
  if (hasMigration) {
    const { execSync } = require('child_process');
    let idempotent = true;
    try {
      if (fs.existsSync(path.join(__dirname, 'migrate.js'))) {
        execSync('node migrate.js', { cwd: __dirname, timeout: 5000 });
        execSync('node migrate.js', { cwd: __dirname, timeout: 5000 });
      }
    } catch (e) { idempotent = false; }
    assert('migration script runs twice without error', idempotent);
  } else {
    assert('migration script runs twice without error', false);
  }

  console.log('\nTest 18: Health check');
  const health = await request('GET', '/health', null).catch(() => ({ status: 500, body: {} }));
  assert('GET /health returns 200', health.status === 200);

  console.log(`\n=== Results: ${passes} passed, ${failures} failed ===`);
  server.close();
  process.exit(failures > 0 ? 1 : 0);
}

runTests().catch(e => {
  console.error('Test runner crashed:', e.message);
  process.exit(1);
});
