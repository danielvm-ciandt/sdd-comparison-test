#!/usr/bin/env node
const http = require('http');
const url = require('url');
const path = require('path');
const fs = require('fs');

const PORT = process.env.PORT || 3003;
const seed = JSON.parse(fs.readFileSync(path.join(__dirname, 'data', 'seed.json'), 'utf8'));

const store = {
  artists: seed.artists,
  albums: seed.albums,
  songs: seed.songs,
  plays: [],
};

function json(res, status, data) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(data));
}

function parseBody(req) {
  return new Promise(resolve => {
    let data = '';
    req.on('data', c => data += c);
    req.on('end', () => { try { resolve(JSON.parse(data)); } catch (e) { resolve({}); } });
  });
}

const server = http.createServer(async (req, res) => {
  const parsed = url.parse(req.url, true);
  const { pathname, query } = parsed;

  if (req.method === 'GET' && pathname === '/artists') {
    return json(res, 200, store.artists);
  }
  if (req.method === 'GET' && pathname === '/albums') {
    return json(res, 200, store.albums);
  }
  if (req.method === 'GET' && pathname === '/songs') {
    return json(res, 200, store.songs);
  }

  // POST /plays, GET /plays, GET /recommendations — NOT IMPLEMENTED
  json(res, 404, { error: 'Not found' });
});

server.listen(PORT, () => {
  process.stdout.write(`Music Store API running on port ${PORT}\n`);
});

module.exports = server;
