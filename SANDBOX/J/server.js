const express = require('express');
const Database = require('better-sqlite3');

const app = express();
app.use(express.json());

const db = new Database(':memory:');

db.exec(`
  CREATE TABLE accounts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    owner TEXT NOT NULL,
    balance INTEGER NOT NULL DEFAULT 0
  );
  CREATE TABLE transactions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    from_account INTEGER,
    to_account INTEGER,
    amount INTEGER NOT NULL,
    created_at TEXT DEFAULT (datetime('now'))
  );
`);

db.prepare('INSERT INTO accounts (owner, balance) VALUES (?, ?)').run('Alice', 100000);
db.prepare('INSERT INTO accounts (owner, balance) VALUES (?, ?)').run('Bob', 50000);

app.get('/health', (req, res) => res.json({ status: 'ok' }));

app.get('/accounts', (req, res) => {
  const accounts = db.prepare('SELECT * FROM accounts').all();
  res.json(accounts);
});

app.post('/accounts', (req, res) => {
  const { owner, balance = 0 } = req.body;
  if (!owner) return res.status(400).json({ error: 'owner required' });
  const id = db.prepare('INSERT INTO accounts (owner, balance) VALUES (?, ?)').run(owner, balance).lastInsertRowid;
  res.status(201).json({ id, owner, balance });
});

app.post('/transactions', (req, res) => {
  const { from_account, to_account, amount } = req.body;
  if (!amount || amount <= 0) return res.status(400).json({ error: 'amount must be positive' });
  const from = db.prepare('SELECT * FROM accounts WHERE id = ?').get(from_account);
  const to = db.prepare('SELECT * FROM accounts WHERE id = ?').get(to_account);
  if (!from || !to) return res.status(404).json({ error: 'account not found' });
  if (from.balance < amount) return res.status(422).json({ error: 'insufficient funds' });
  db.prepare('UPDATE accounts SET balance = balance - ? WHERE id = ?').run(amount, from_account);
  db.prepare('UPDATE accounts SET balance = balance + ? WHERE id = ?').run(amount, to_account);
  const id = db.prepare('INSERT INTO transactions (from_account, to_account, amount) VALUES (?, ?, ?)').run(from_account, to_account, amount).lastInsertRowid;
  res.status(201).json({ id, from_account, to_account, amount });
});

app.get('/transactions', (req, res) => {
  const txns = db.prepare('SELECT * FROM transactions').all();
  res.json(txns);
});

const PORT = process.env.PORT || 3006;
const server = app.listen(PORT, () => {
  process.stdout.write(`Banking API running on port ${PORT}\n`);
});

module.exports = { app, server, db };
