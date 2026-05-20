#!/usr/bin/env node
const http = require('http');
const fs = require('fs');
const url = require('url');
const path = require('path');

const PORT = process.env.PORT || 3001;
const elements = JSON.parse(fs.readFileSync(path.join(__dirname, 'data', 'elements.json'), 'utf8'));

const server = http.createServer((req, res) => {
  const parsed = url.parse(req.url, true);
  const pathname = parsed.pathname;
  const query = parsed.query;

  res.setHeader('Content-Type', 'application/json');

  // GET /elements or GET /elements?category=X
  if (req.method === 'GET' && pathname === '/elements') {
    let result = elements;
    if (query.category) {
      result = elements.filter(e => e.category && e.category.toLowerCase() === query.category.toLowerCase());
    }
    res.writeHead(200);
    res.end(JSON.stringify(result));
    return;
  }

  // GET /elements/:symbol
  const symbolMatch = pathname.match(/^\/elements\/([^/]+)$/);
  if (req.method === 'GET' && symbolMatch) {
    const sym = symbolMatch[1].charAt(0).toUpperCase() + symbolMatch[1].slice(1).toLowerCase();
    const element = elements.find(e => e.symbol === sym || e.symbol.toLowerCase() === symbolMatch[1].toLowerCase());
    if (!element) {
      res.writeHead(404);
      res.end(JSON.stringify({ error: 'Not found' }));
      return;
    }
    res.writeHead(200);
    res.end(JSON.stringify(element));
    return;
  }

  res.writeHead(404);
  res.end(JSON.stringify({ error: 'Not found' }));
});

server.listen(PORT, () => {
  process.stdout.write(`Element API running on port ${PORT}\n`);
});

module.exports = server;
