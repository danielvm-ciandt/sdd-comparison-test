/**
 * SABR Task A — Leaky Proxy (BROKEN BASELINE)
 *
 * This is a TCP-level HTTP proxy that forwards requests to an upstream server.
 *
 * BUG: When the upstream connection fails (ECONNREFUSED, ETIMEDOUT, etc.),
 * the socket is never destroyed and the client response is never ended.
 * Under load this exhausts file descriptors and crashes the process.
 *
 * Goal: Identify the root cause and fix the leak so detect-leak.js reports 0 leaked sockets.
 */

'use strict';

const net = require('net');
const http = require('http');

const PROXY_PORT = 3000;
const UPSTREAM_HOST = process.env.UPSTREAM_HOST || 'localhost';
const UPSTREAM_PORT = parseInt(process.env.UPSTREAM_PORT || '8080', 10);

const server = http.createServer((req, res) => {
  const upstream = net.connect(UPSTREAM_PORT, UPSTREAM_HOST, () => {
    // Build a minimal HTTP/1.1 request to forward upstream
    const reqLine = `${req.method} ${req.url} HTTP/1.1\r\n`;
    const headers = Object.entries(req.headers)
      .map(([k, v]) => `${k}: ${v}`)
      .join('\r\n');
    upstream.write(reqLine + headers + '\r\n\r\n');

    req.pipe(upstream);
    upstream.pipe(res);
  });

  // ────────────────────────────────────────────────────────────────────────
  // BUG: No error handler on `upstream`.
  // When upstream is unavailable, 'error' is emitted on the socket.
  // Without a handler Node.js treats it as an uncaught exception (or
  // silently drops it if another listener is attached), but crucially the
  // socket is never destroyed and `res` is never ended — the client hangs
  // and the file descriptor leaks.
  //
  // Fix should include:
  //   upstream.on('error', (err) => {
  //     upstream.destroy();
  //     if (!res.headersSent) res.writeHead(502);
  //     res.end(`Bad Gateway: ${err.message}`);
  //   });
  //   req.on('error', () => upstream.destroy());
  // ────────────────────────────────────────────────────────────────────────
});

server.on('error', (err) => {
  console.error('[proxy] server error:', err.message);
});

server.listen(PROXY_PORT, () => {
  console.log(`[proxy] listening on port ${PROXY_PORT} → ${UPSTREAM_HOST}:${UPSTREAM_PORT}`);
});

module.exports = server;
