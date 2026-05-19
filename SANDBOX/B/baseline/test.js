/**
 * SABR Task B — Acceptance Tests
 *
 * All tests FAIL on the baseline (billing not implemented).
 * The agent must implement subscriptions + invoicing to make them pass.
 *
 * Run: node test.js
 */
'use strict';

const http = require('http');

// Start the server
const { app, server } = require('./server');

const PORT = process.env.TEST_PORT || process.env.PORT || '3001';
const BASE = `http://localhost:${PORT}`;
let passed = 0;
let failed = 0;

function assert(condition, msg) {
  if (condition) { console.log(`  ✓ ${msg}`); passed++; }
  else           { console.error(`  ✗ ${msg}`); failed++; }
}

function request(method, path, body) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, BASE);
    const payload = body ? JSON.stringify(body) : null;
    const options = {
      hostname: url.hostname,
      port: url.port,
      path: url.pathname,
      method,
      headers: {
        'Content-Type': 'application/json',
        ...(payload ? { 'Content-Length': Buffer.byteLength(payload) } : {}),
      },
    };
    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', chunk => { data += chunk; });
      res.on('end', () => {
        try { resolve({ status: res.statusCode, body: JSON.parse(data) }); }
        catch { resolve({ status: res.statusCode, body: data }); }
      });
    });
    req.on('error', reject);
    if (payload) req.write(payload);
    req.end();
  });
}

async function runTests() {
  console.log('SABR Task B — Billing Slice Acceptance Tests\n');

  await new Promise(r => setTimeout(r, 300)); // wait for server

  // ── Subscriptions ────────────────────────────────────────────────────────

  console.log('[ Subscriptions ]');

  // Subscribe user 1 to the pro plan
  let sub;
  {
    const r = await request('POST', '/subscriptions', { userId: 1, planId: 'pro' });
    assert(r.status === 201, `POST /subscriptions → 201 (got ${r.status})`);
    sub = r.body;
    assert(sub && sub.id,          'response has an id');
    assert(sub.userId === 1,       'response.userId === 1');
    assert(sub.planId === 'pro',   'response.planId === "pro"');
    assert(sub.status === 'active','response.status === "active"');
    assert(sub.startedAt,          'response has startedAt');
  }

  // Get the subscription back
  {
    const r = await request('GET', '/subscriptions/1');
    assert(r.status === 200,       `GET /subscriptions/1 → 200 (got ${r.status})`);
    assert(r.body.planId === 'pro','active plan is "pro"');
  }

  // Cannot subscribe again while already subscribed
  {
    const r = await request('POST', '/subscriptions', { userId: 1, planId: 'starter' });
    assert(r.status === 409, `POST /subscriptions when already subscribed → 409 (got ${r.status})`);
  }

  // Unknown user cannot subscribe
  {
    const r = await request('POST', '/subscriptions', { userId: 999, planId: 'pro' });
    assert(r.status === 404, `POST /subscriptions unknown user → 404 (got ${r.status})`);
  }

  // Unknown plan cannot be subscribed to
  {
    const r = await request('POST', '/subscriptions', { userId: 2, planId: 'nonexistent' });
    assert(r.status === 404, `POST /subscriptions unknown plan → 404 (got ${r.status})`);
  }

  // ── Invoices ─────────────────────────────────────────────────────────────

  console.log('\n[ Invoices ]');

  // Generate invoice for user 1 (subscribed to pro @ $29.99)
  let invoice;
  {
    const r = await request('POST', '/invoices/generate/1');
    assert(r.status === 201,       `POST /invoices/generate/1 → 201 (got ${r.status})`);
    invoice = r.body;
    assert(invoice && invoice.id,           'invoice has id');
    assert(invoice.userId === 1,            'invoice.userId === 1');
    assert(Array.isArray(invoice.lineItems),'invoice has lineItems array');
    assert(invoice.lineItems.length > 0,   'invoice has at least one line item');
    assert(typeof invoice.subtotal === 'number', 'invoice.subtotal is a number');
    assert(typeof invoice.tax === 'number',      'invoice.tax is a number');
    assert(typeof invoice.total === 'number',    'invoice.total is a number');
    assert(invoice.total >= invoice.subtotal,    'total >= subtotal');
    assert(invoice.currency === 'USD' || invoice.currency === 'usd', 'invoice currency is USD');
  }

  // List invoices for user 1
  {
    const r = await request('GET', '/invoices/1');
    assert(r.status === 200,             `GET /invoices/1 → 200 (got ${r.status})`);
    assert(Array.isArray(r.body),        'returns array');
    assert(r.body.length >= 1,           'at least 1 invoice in list');
    assert(r.body[0].id === invoice.id,  'most recent invoice is first');
  }

  // Cannot generate invoice for user with no subscription
  {
    const r = await request('POST', '/invoices/generate/2');
    assert(r.status === 404 || r.status === 400,
      `POST /invoices/generate for unsubscribed user → 4xx (got ${r.status})`);
  }

  // ── Cancel subscription ──────────────────────────────────────────────────

  console.log('\n[ Cancellation ]');

  {
    const r = await request('DELETE', '/subscriptions/1');
    assert(r.status === 200 || r.status === 204,
      `DELETE /subscriptions/1 → 2xx (got ${r.status})`);
  }

  // After cancellation, subscription status should reflect it
  {
    const r = await request('GET', '/subscriptions/1');
    if (r.status === 200) {
      assert(r.body.status === 'cancelled', 'subscription status is "cancelled" after DELETE');
    } else {
      assert(r.status === 404, `subscription returns 404 after cancel (got ${r.status})`);
    }
  }

  // ── Summary ───────────────────────────────────────────────────────────────

  console.log(`\n${'─'.repeat(40)}`);
  console.log(`${passed} passed, ${failed} failed`);

  server.close();
  process.exit(failed > 0 ? 1 : 0);
}

runTests().catch(err => {
  console.error('Test runner error:', err);
  server.close();
  process.exit(1);
});
