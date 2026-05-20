#!/usr/bin/env node
const http = require('http');
const fs = require('fs');
const url = require('url');
const path = require('path');

const PORT = process.env.PORT || 3001;

// BUG: elements is never loaded
let elements = [];

const server = http.createServer((req, res) => {
  const parsed = url.parse(req.url, true);
  const pathname = parsed.pathname;
  const query = parsed.query;

  res.setHeader('Content-Type', 'application/json');

  // GET /elements or GET /elements?category=X
  if (req.method === 'GET' && pathname === '/elements') {
    // BUG: returns empty array instead of data
    res.writeHead(200);
    res.end(JSON.stringify([]));
    return;
  }

  // GET /elements/:symbol
  const symbolMatch = pathname.match(/^\/elements\/([^/]+)$/);
  if (req.method === 'GET' && symbolMatch) {
    // BUG: always returns 404
    res.writeHead(404);
    res.end(JSON.stringify({ error: 'Not found' }));
    return;
  }

  res.writeHead(404);
  res.end(JSON.stringify({ error: 'Not found' }));
});

server.listen(PORT, () => {
  process.stdout.write(`Element API stub running on port ${PORT}\n`);
});

module.exports = server;
