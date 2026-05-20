/**
 * detect-leak.js — Socket leak detector for SABR Task A
 *
 * Sends N requests to the proxy pointing at a closed upstream port,
 * then checks how many sockets remain open after a grace period.
 *
 * Usage:  node detect-leak.js [requests=20] [grace_ms=2000]
 * Exit 0: no leak detected (all sockets closed within grace period)
 * Exit 1: leak detected (open sockets remain)
 */

'use strict';

const http = require('http');
const net = require('net');

const PROXY_PORT = 3000;
const REQUESTS = parseInt(process.argv[2] || '20', 10);
const GRACE_MS = parseInt(process.argv[3] || '2000', 10);

// Track open sockets we create
let openSockets = 0;
let completed = 0;

function sendRequest() {
  return new Promise((resolve) => {
    const req = http.get(
      { host: 'localhost', port: PROXY_PORT, path: '/', timeout: 1000 },
      (res) => {
        res.resume();
        res.on('end', resolve);
        res.on('error', resolve);
      }
    );
    req.on('socket', (sock) => {
      openSockets++;
      sock.on('close', () => { openSockets--; });
    });
    req.on('error', resolve);
    req.on('timeout', () => { req.destroy(); resolve(); });
  });
}

(async () => {
  console.log(`[detect-leak] Sending ${REQUESTS} requests to proxy (upstream is intentionally closed)...`);

  const promises = [];
  for (let i = 0; i < REQUESTS; i++) {
    promises.push(sendRequest());
  }

  await Promise.allSettled(promises);

  console.log(`[detect-leak] All requests fired. Waiting ${GRACE_MS}ms for sockets to close...`);
  await new Promise(r => setTimeout(r, GRACE_MS));

  console.log(`[detect-leak] Open sockets after grace period: ${openSockets}`);

  if (openSockets === 0) {
    console.log('[detect-leak] PASS — no socket leak detected.');
    process.exit(0);
  } else {
    console.log(`[detect-leak] FAIL — ${openSockets} sockets still open (LEAK DETECTED).`);
    process.exit(1);
  }
})();
