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
  CREATE TABLE dependencies (
    task_id INTEGER NOT NULL,
    depends_on INTEGER NOT NULL,
    PRIMARY KEY (task_id, depends_on)
  );
  CREATE TABLE teams (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT);
  CREATE TABLE members (team_id INTEGER, user_id INTEGER, role TEXT);
`);

const p1 = db.prepare('INSERT INTO projects (name) VALUES (?)').run('Alpha').lastInsertRowid;
const t1 = db.prepare('INSERT INTO tasks (project_id, title) VALUES (?, ?)').run(p1, 'Design schema').lastInsertRowid;
const t2 = db.prepare('INSERT INTO tasks (project_id, title) VALUES (?, ?)').run(p1, 'Implement API').lastInsertRowid;
const t3 = db.prepare('INSERT INTO tasks (project_id, title) VALUES (?, ?)').run(p1, 'Write tests').lastInsertRowid;

function getBlockedBy(taskId) {
  const deps = db.prepare('SELECT depends_on FROM dependencies WHERE task_id = ?').all(taskId);
  return deps.map(d => d.depends_on).sort((a, b) => a - b);
}

function isBlocked(taskId) {
  const deps = getBlockedBy(taskId);
  for (const depId of deps) {
    const dep = db.prepare('SELECT status FROM tasks WHERE id = ?').get(depId);
    if (!dep || dep.status !== 'done') return true;
  }
  return false;
}

function hasCycle(taskId, dependsOn) {
  // Would adding "taskId depends_on dependsOn" create a cycle?
  // A cycle exists if dependsOn already (transitively) depends on taskId.
  // BFS: starting from dependsOn, follow depends_on edges upward.
  const visited = new Set();
  const queue = [dependsOn];
  while (queue.length) {
    const cur = queue.shift();
    if (cur === taskId) return true;
    if (visited.has(cur)) continue;
    visited.add(cur);
    // cur depends_on these tasks (cur's own dependencies)
    const curDeps = db.prepare('SELECT depends_on FROM dependencies WHERE task_id = ?').all(cur);
    queue.push(...curDeps.map(d => d.depends_on));
  }
  return false;
}

function enrichTask(task) {
  return { ...task, blockedBy: getBlockedBy(task.id) };
}

app.get('/projects', (req, res) => res.json(db.prepare('SELECT * FROM projects').all()));
app.post('/projects', (req, res) => {
  const { name } = req.body;
  const id = db.prepare('INSERT INTO projects (name) VALUES (?)').run(name).lastInsertRowid;
  res.status(201).json({ id, name, status: 'active' });
});

app.get('/projects/:id/tasks', (req, res) => {
  const tasks = db.prepare('SELECT * FROM tasks WHERE project_id = ?').all(req.params.id);
  res.json(tasks.map(enrichTask));
});

app.get('/tasks', (req, res) => {
  const { status } = req.query;
  let tasks;
  if (status === 'blocked') {
    const allTasks = db.prepare('SELECT * FROM tasks').all();
    tasks = allTasks.filter(t => isBlocked(t.id));
  } else if (status) {
    tasks = db.prepare('SELECT * FROM tasks WHERE status = ?').all(status);
  } else {
    tasks = db.prepare('SELECT * FROM tasks').all();
  }
  res.json(tasks.map(enrichTask));
});

app.get('/tasks/:id', (req, res) => {
  const task = db.prepare('SELECT * FROM tasks WHERE id = ?').get(req.params.id);
  if (!task) return res.status(404).json({ error: 'not found' });
  res.json(enrichTask(task));
});

app.post('/tasks', (req, res) => {
  const { project_id, title } = req.body;
  const id = db.prepare('INSERT INTO tasks (project_id, title) VALUES (?, ?)').run(project_id, title).lastInsertRowid;
  res.status(201).json({ id, project_id, title, status: 'todo', blockedBy: [] });
});

app.patch('/tasks/:id', (req, res) => {
  const { status, force } = req.body;
  const taskId = +req.params.id;
  const task = db.prepare('SELECT * FROM tasks WHERE id = ?').get(taskId);
  if (!task) return res.status(404).json({ error: 'not found' });
  if (status === 'started' && !force && isBlocked(taskId)) {
    return res.status(409).json({ error: 'task is blocked by unfinished dependencies' });
  }
  db.prepare('UPDATE tasks SET status = ? WHERE id = ?').run(status, taskId);
  const updated = db.prepare('SELECT * FROM tasks WHERE id = ?').get(taskId);
  res.json(enrichTask(updated));
});

// Dependencies
app.post('/tasks/:id/dependencies', (req, res) => {
  const taskId = +req.params.id;
  const { dependsOn } = req.body;
  const dep = db.prepare('SELECT * FROM tasks WHERE id = ?').get(dependsOn);
  if (!dep) return res.status(400).json({ error: 'dependency task not found' });
  if (hasCycle(taskId, dependsOn) || taskId === dependsOn) {
    return res.status(400).json({ error: 'circular dependency' });
  }
  try {
    db.prepare('INSERT OR IGNORE INTO dependencies (task_id, depends_on) VALUES (?, ?)').run(taskId, dependsOn);
    res.status(201).json({ taskId, dependsOn });
  } catch (e) {
    res.status(400).json({ error: e.message });
  }
});

app.delete('/tasks/:id/dependencies/:depId', (req, res) => {
  db.prepare('DELETE FROM dependencies WHERE task_id = ? AND depends_on = ?').run(req.params.id, req.params.depId);
  res.status(200).json({ ok: true });
});

app.delete('/tasks/:id/dependencies', (req, res) => {
  db.prepare('DELETE FROM dependencies WHERE task_id = ?').run(req.params.id);
  res.status(200).json({ ok: true });
});

const PORT = process.env.PORT || 3005;
const server = app.listen(PORT, () => {
  process.stdout.write(`Project Tracker API running on port ${PORT}\n`);
});

module.exports = { app, server, db };
