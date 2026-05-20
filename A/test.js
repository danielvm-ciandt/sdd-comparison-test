/**
 * SABR Task A — Test Suite
 *
 * Verifies the proxy fails fast (502) when upstream is unreachable.
 * On the BROKEN baseline all tests fail because the proxy hangs forever.
 */
'use strict';

const http = require('http');

// Import server (starts listening immediately)
const server = require('./server');

let passed = 0;
let failed = 0;

function assert(condition, msg) {
  if (condition) { console.log(`  ✓ ${msg}`); passed++; }
  else           { console.error(`  ✗ ${msg}`); failed++; }
}

async function testFailsFast() {
  return new Promise((resolve) => {
    const start = Date.now();
    const req = http.get(
      { host: 'localhost', port: 3000, path: '/', timeout: 3000 },
      (res) => {
        const ms = Date.now() - start;
        assert(res.statusCode === 502, `responds 502 when upstream is down (got ${res.statusCode})`);
        assert(ms < 3000,             `responds in <3s (took ${ms}ms)`);
        res.resume();
        res.on('end', resolve);
      }
    );
    req.on('error', (err) => {
      const ms = Date.now() - start;
      assert(ms < 3000, `fails fast on network error (took ${ms}ms): ${err.code}`);
      resolve();
    });
    req.on('timeout', () => {
      assert(false, 'request timed out — proxy is HANGING (socket leak)');
      req.destroy();
      resolve();
    });
  });
}

async function testMultipleRequestsDontHang() {
  const reqs = Array.from({ length: 5 }, () => testFailsFast());
  await Promise.all(reqs);
  assert(true, '5 concurrent requests all resolved without hanging');
}

(async () => {
  console.log('SABR Task A — Leaky Proxy\n');
  await new Promise(r => setTimeout(r, 300)); // wait for server
  await testFailsFast();
  await testMultipleRequestsDontHang();
  console.log(`\n${passed} passed, ${failed} failed`);
  server.close();
  process.exit(failed > 0 ? 1 : 0);
})();
