// Task F: Todo API with JWT authentication
const express = require('express');
const Database = require('better-sqlite3');
const crypto = require('crypto');

const app = express();
app.use(express.json());

const db = new Database(':memory:');

db.exec(`
  CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, email TEXT UNIQUE, password TEXT);
  CREATE TABLE tasks (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER, title TEXT, done INTEGER DEFAULT 0);
  CREATE TABLE revoked_tokens (token TEXT PRIMARY KEY, revoked_at TEXT);
`);

const JWT_SECRET = process.env.JWT_SECRET || 'sabr-secret-f-2026';

function base64url(obj) {
  return Buffer.from(JSON.stringify(obj)).toString('base64url');
}

function signToken(payload) {
  const header = base64url({ alg: 'HS256', typ: 'JWT' });
  const body = base64url(payload);
  const sig = crypto.createHmac('sha256', JWT_SECRET).update(`${header}.${body}`).digest('base64url');
  return `${header}.${body}.${sig}`;
}

function verifyToken(token) {
  if (!token) return null;
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  const [header, body, sig] = parts;
  const expected = crypto.createHmac('sha256', JWT_SECRET).update(`${header}.${body}`).digest('base64url');
  if (sig !== expected) return null;
  try {
    return JSON.parse(Buffer.from(body, 'base64url').toString());
  } catch { return null; }
}

function requireAuth(req, res, next) {
  const auth = req.headers['authorization'] || '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'unauthorized' });
  const isRevoked = db.prepare('SELECT 1 FROM revoked_tokens WHERE token = ?').get(token);
  if (isRevoked) return res.status(401).json({ error: 'token revoked' });
  const payload = verifyToken(token);
  if (!payload) return res.status(401).json({ error: 'invalid token' });
  req.userId = payload.userId;
  req._token = token;
  next();
}

// Auth routes
app.post('/auth/signup', (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) return res.status(400).json({ error: 'email and password required' });
  const hash = crypto.createHash('sha256').update(password).digest('hex');
  try {
    const result = db.prepare('INSERT INTO users (email, password) VALUES (?, ?)').run(email, hash);
    const userId = result.lastInsertRowid;
    const token = signToken({ userId });
    res.status(201).json({ id: userId, email, token });
  } catch (e) {
    res.status(400).json({ error: 'email already exists' });
  }
});

app.post('/auth/login', (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) return res.status(400).json({ error: 'email and password required' });
  const hash = crypto.createHash('sha256').update(password).digest('hex');
  const user = db.prepare('SELECT * FROM users WHERE email = ? AND password = ?').get(email, hash);
  if (!user) return res.status(401).json({ error: 'invalid credentials' });
  const token = signToken({ userId: user.id });
  res.status(200).json({ token });
});

app.post('/auth/logout', requireAuth, (req, res) => {
  db.prepare('INSERT OR IGNORE INTO revoked_tokens (token, revoked_at) VALUES (?, ?)').run(req._token, new Date().toISOString());
  res.status(200).json({ ok: true });
});

// Tasks (scoped to user)
app.get('/tasks', requireAuth, (req, res) => {
  const tasks = db.prepare('SELECT * FROM tasks WHERE user_id = ?').all(req.userId);
  res.json(tasks);
});

app.post('/tasks', requireAuth, (req, res) => {
  const { title } = req.body;
  if (!title) return res.status(400).json({ error: 'title required' });
  const result = db.prepare('INSERT INTO tasks (user_id, title) VALUES (?, ?)').run(req.userId, title);
  res.status(201).json({ id: result.lastInsertRowid, user_id: req.userId, title, done: 0 });
});

app.delete('/tasks/:id', requireAuth, (req, res) => {
  db.prepare('DELETE FROM tasks WHERE id = ? AND user_id = ?').run(req.params.id, req.userId);
  res.status(204).send();
});

// Legacy user creation still works
app.post('/users', (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) return res.status(400).json({ error: 'email and password required' });
  const hash = crypto.createHash('sha256').update(password).digest('hex');
  try {
    const result = db.prepare('INSERT INTO users (email, password) VALUES (?, ?)').run(email, hash);
    res.status(201).json({ id: result.lastInsertRowid, email });
  } catch (e) {
    res.status(400).json({ error: 'email already exists' });
  }
});

const PORT = process.env.PORT || 3002;
const server = app.listen(PORT, () => {
  process.stdout.write(`Todo API running on port ${PORT}\n`);
});

module.exports = { app, server, db };
