const express = require('express');
const Database = require('better-sqlite3');

const app = express();
app.use(express.json());

const db = new Database(':memory:');

db.exec(`
  CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, email TEXT UNIQUE, password TEXT);
  CREATE TABLE tasks (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER, title TEXT, done INTEGER DEFAULT 0);
`);

app.post('/users', (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) return res.status(400).json({ error: 'email and password required' });
  try {
    const stmt = db.prepare('INSERT INTO users (email, password) VALUES (?, ?)');
    const result = stmt.run(email, password);
    res.status(201).json({ id: result.lastInsertRowid, email });
  } catch (e) {
    res.status(400).json({ error: 'email already exists' });
  }
});

app.get('/tasks', (req, res) => {
  const tasks = db.prepare('SELECT * FROM tasks').all();
  res.json(tasks);
});

app.post('/tasks', (req, res) => {
  const { user_id, title } = req.body;
  if (!title) return res.status(400).json({ error: 'title required' });
  const result = db.prepare('INSERT INTO tasks (user_id, title) VALUES (?, ?)').run(user_id || null, title);
  res.status(201).json({ id: result.lastInsertRowid, user_id, title, done: 0 });
});

app.delete('/tasks/:id', (req, res) => {
  db.prepare('DELETE FROM tasks WHERE id = ?').run(req.params.id);
  res.status(204).send();
});

const PORT = process.env.PORT || 3002;
const server = app.listen(PORT, () => {
  process.stdout.write(`Todo API running on port ${PORT}\n`);
});

module.exports = { app, server, db };
