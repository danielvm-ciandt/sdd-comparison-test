'use strict';
const net = require('net');
const http = require('http');

const PROXY_PORT = 3000;
const UPSTREAM_HOST = process.env.UPSTREAM_HOST || 'localhost';
const UPSTREAM_PORT = parseInt(process.env.UPSTREAM_PORT || '8080', 10);

const server = http.createServer((req, res) => {
  const upstream = net.connect(UPSTREAM_PORT, UPSTREAM_HOST, () => {
    const reqLine = `${req.method} ${req.url} HTTP/1.1\r\n`;
    const headers = Object.entries(req.headers)
      .map(([k, v]) => `${k}: ${v}`)
      .join('\r\n');
    upstream.write(reqLine + headers + '\r\n\r\n');
    req.pipe(upstream);
    upstream.pipe(res);
  });

  upstream.on('error', (err) => {
    upstream.destroy();
    if (!res.headersSent) res.writeHead(502);
    res.end(`Bad Gateway: ${err.message}`);
  });

  req.on('error', () => upstream.destroy());
  req.on('aborted', () => upstream.destroy());
  upstream.setTimeout(5000, () => {
    upstream.destroy();
    if (!res.headersSent) res.writeHead(502);
    res.end('Bad Gateway: upstream timeout');
  });
});

server.on('error', (err) => {
  console.error('[proxy] server error:', err.message);
});

server.listen(PROXY_PORT, () => {
  console.log(`[proxy] listening on port ${PROXY_PORT} → ${UPSTREAM_HOST}:${UPSTREAM_PORT}`);
});

module.exports = server;
