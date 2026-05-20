const express = require('express');
const Database = require('better-sqlite3');

const app = express();
app.use(express.json());

const db = new Database(':memory:');

db.exec(`
  CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT);
  CREATE TABLE conversations (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT);
  CREATE TABLE participants (conversation_id INTEGER, user_id INTEGER);
  CREATE TABLE messages (id INTEGER PRIMARY KEY AUTOINCREMENT, conversation_id INTEGER, user_id INTEGER, body TEXT, created_at TEXT);
`);

const u1 = db.prepare('INSERT INTO users (name) VALUES (?)').run('Alice').lastInsertRowid;
const u2 = db.prepare('INSERT INTO users (name) VALUES (?)').run('Bob').lastInsertRowid;
const c1 = db.prepare('INSERT INTO conversations (name) VALUES (?)').run('general').lastInsertRowid;
db.prepare('INSERT INTO participants VALUES (?, ?)').run(c1, u1);
db.prepare('INSERT INTO participants VALUES (?, ?)').run(c1, u2);

// GET /users — BUG: no `online` field
app.get('/users', (req, res) => {
  const users = db.prepare('SELECT id, name FROM users').all();
  res.json(users);
});

// GET /users/:id — BUG: no `online` field
app.get('/users/:id', (req, res) => {
  const user = db.prepare('SELECT id, name FROM users WHERE id = ?').get(req.params.id);
  if (!user) return res.status(404).json({ error: 'not found' });
  res.json(user);
});

// GET /conversations/:id — BUG: participants have no `online` field
app.get('/conversations/:id', (req, res) => {
  const conv = db.prepare('SELECT * FROM conversations WHERE id = ?').get(req.params.id);
  if (!conv) return res.status(404).json({ error: 'not found' });
  const participants = db.prepare(
    'SELECT u.id, u.name FROM users u JOIN participants p ON u.id = p.user_id WHERE p.conversation_id = ?'
  ).all(req.params.id);
  res.json({ ...conv, participants });
});

app.post('/conversations', (req, res) => {
  const { name } = req.body;
  const id = db.prepare('INSERT INTO conversations (name) VALUES (?)').run(name).lastInsertRowid;
  res.status(201).json({ id, name });
});

const PORT = process.env.PORT || 3004;
const server = app.listen(PORT, () => {
  process.stdout.write(`Chat API running on port ${PORT}\n`);
});

module.exports = { app, server, db };
