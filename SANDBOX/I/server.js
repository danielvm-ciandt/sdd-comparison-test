const express = require('express');
const Database = require('better-sqlite3');

const app = express();
app.use(express.json());

const db = new Database(':memory:');

db.exec(`
  CREATE TABLE projects (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, status TEXT DEFAULT 'active');
  CREATE TABLE tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER,
    title TEXT,
    status TEXT DEFAULT 'todo'
  );
  CREATE TABLE teams (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT);
  CREATE TABLE members (team_id INTEGER, user_id INTEGER, role TEXT);
`);

const p1 = db.prepare('INSERT INTO projects (name) VALUES (?)').run('Alpha').lastInsertRowid;
const t1 = db.prepare('INSERT INTO tasks (project_id, title) VALUES (?, ?)').run(p1, 'Design schema').lastInsertRowid;
const t2 = db.prepare('INSERT INTO tasks (project_id, title) VALUES (?, ?)').run(p1, 'Implement API').lastInsertRowid;
const t3 = db.prepare('INSERT INTO tasks (project_id, title) VALUES (?, ?)').run(p1, 'Write tests').lastInsertRowid;

app.get('/projects', (req, res) => res.json(db.prepare('SELECT * FROM projects').all()));
app.post('/projects', (req, res) => {
  const { name } = req.body;
  const id = db.prepare('INSERT INTO projects (name) VALUES (?)').run(name).lastInsertRowid;
  res.status(201).json({ id, name, status: 'active' });
});

app.get('/projects/:id/tasks', (req, res) => {
  const tasks = db.prepare('SELECT * FROM tasks WHERE project_id = ?').all(req.params.id);
  res.json(tasks);
});

app.get('/tasks', (req, res) => {
  const { status } = req.query;
  const tasks = status
    ? db.prepare('SELECT * FROM tasks WHERE status = ?').all(status)
    : db.prepare('SELECT * FROM tasks').all();
  res.json(tasks);
});

app.get('/tasks/:id', (req, res) => {
  const task = db.prepare('SELECT * FROM tasks WHERE id = ?').get(req.params.id);
  if (!task) return res.status(404).json({ error: 'not found' });
  res.json(task);
});

app.post('/tasks', (req, res) => {
  const { project_id, title } = req.body;
  const id = db.prepare('INSERT INTO tasks (project_id, title) VALUES (?, ?)').run(project_id, title).lastInsertRowid;
  res.status(201).json({ id, project_id, title, status: 'todo' });
});

app.patch('/tasks/:id', (req, res) => {
  const { status } = req.body;
  db.prepare('UPDATE tasks SET status = ? WHERE id = ?').run(status, req.params.id);
  const task = db.prepare('SELECT * FROM tasks WHERE id = ?').get(req.params.id);
  res.json(task);
});

const PORT = process.env.PORT || 3005;
const server = app.listen(PORT, () => {
  process.stdout.write(`Project Tracker API running on port ${PORT}\n`);
});

module.exports = { app, server, db };
