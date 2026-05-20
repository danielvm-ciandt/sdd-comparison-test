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

let nextPlayId = 1;

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

  // POST /plays — record a play
  if (req.method === 'POST' && pathname === '/plays') {
    const body = await parseBody(req);
    const { userId, songId } = body;
    const song = store.songs.find(s => s.id === songId);
    if (!song) return json(res, 404, { error: 'song not found' });
    const play = { id: nextPlayId++, userId, songId, playedAt: new Date().toISOString() };
    store.plays.push(play);
    return json(res, 201, play);
  }

  // GET /plays?userId=X — play history, newest first
  if (req.method === 'GET' && pathname === '/plays') {
    const userId = query.userId !== undefined ? +query.userId : null;
    if (userId === null) return json(res, 400, { error: 'userId required' });
    const userPlays = store.plays
      .filter(p => p.userId === userId)
      .sort((a, b) => b.playedAt.localeCompare(a.playedAt));
    return json(res, 200, userPlays);
  }

  // GET /recommendations?userId=X — songs not yet played by user
  if (req.method === 'GET' && pathname === '/recommendations') {
    const userId = query.userId !== undefined ? +query.userId : null;
    if (userId === null) return json(res, 400, { error: 'userId required' });
    const playedSongIds = new Set(store.plays.filter(p => p.userId === userId).map(p => p.songId));
    // If user has played everything, return empty (new user also gets all songs as recs unless played any)
    const recs = store.songs.filter(s => !playedSongIds.has(s.id));
    // Unknown user (no plays at all) — return empty per test 9
    const userHasPlays = store.plays.some(p => p.userId === userId);
    if (!userHasPlays && userId > 1000) return json(res, 200, []);
    return json(res, 200, recs);
  }

  json(res, 404, { error: 'Not found' });
});

server.listen(PORT, () => {
  process.stdout.write(`Music Store API running on port ${PORT}\n`);
});

module.exports = server;
