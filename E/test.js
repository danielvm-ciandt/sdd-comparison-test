#!/usr/bin/env node
const http = require('http');
const path = require('path');

const PORT = 3001;
let passes = 0;
let failures = 0;

function assert(name, condition) {
  if (condition) {
    console.log(`  ✓ ${name}`);
    passes++;
  } else {
    console.log(`  ✗ ${name}`);
    failures++;
  }
}

function get(urlPath) {
  return new Promise((resolve, reject) => {
    http.get(`http://localhost:${PORT}${urlPath}`, (res) => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => {
        try { resolve({ status: res.statusCode, body: JSON.parse(data) }); }
        catch (e) { resolve({ status: res.statusCode, body: data }); }
      });
    }).on('error', reject);
  });
}

const elements = JSON.parse(
  require('fs').readFileSync(path.join(__dirname, 'data', 'elements.json'), 'utf8')
);
const EXPECTED_COUNT = elements.length;
const NONMETAL_COUNT = elements.filter(e => e.category === 'nonmetal').length;

async function runTests() {
  console.log('=== Element Filter API Test Suite ===\n');

  const server = require('./server');
  await new Promise(r => setTimeout(r, 100));

  console.log('Test 1: List all elements');
  try {
    const res = await get('/elements');
    assert(`GET /elements returns ${EXPECTED_COUNT} items`, Array.isArray(res.body) && res.body.length === EXPECTED_COUNT);
  } catch (e) { assert('GET /elements returns all elements', false); }

  console.log('\nTest 2: Category filter');
  try {
    const res = await get('/elements?category=nonmetal');
    assert(`GET /elements?category=nonmetal returns ${NONMETAL_COUNT} items`,
      Array.isArray(res.body) && res.body.length === NONMETAL_COUNT &&
      res.body.every(e => e.category === 'nonmetal'));
  } catch (e) { assert('category filter returns correct subset', false); }

  console.log('\nTest 3: Symbol lookup');
  try {
    const res = await get('/elements/H');
    assert('GET /elements/H returns Hydrogen',
      res.status === 200 && res.body.name === 'Hydrogen' && res.body.symbol === 'H');
  } catch (e) { assert('symbol lookup returns correct element', false); }

  console.log('\nTest 4: Unknown symbol');
  try {
    const res = await get('/elements/XX');
    assert('GET /elements/XX returns 404', res.status === 404);
  } catch (e) { assert('unknown symbol returns 404', false); }

  console.log('\nTest 5: Response shape');
  try {
    const res = await get('/elements/He');
    const e = res.body;
    assert('response has symbol, name, atomicNumber, atomicMass, category',
      res.status === 200 &&
      typeof e.symbol === 'string' &&
      typeof e.name === 'string' &&
      typeof e.atomicNumber === 'number' &&
      typeof e.atomicMass === 'number' &&
      typeof e.category === 'string');
  } catch (e) { assert('response shape matches contract', false); }

  console.log(`\n=== Results: ${passes} passed, ${failures} failed ===`);
  server.close();
  process.exit(failures > 0 ? 1 : 0);
}

runTests().catch(e => {
  console.error('Test runner crashed:', e.message);
  process.exit(1);
});
