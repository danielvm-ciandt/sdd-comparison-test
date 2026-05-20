const express = require('express');
const Database = require('better-sqlite3');

const app = express();
app.use(express.json());

const db = new Database(':memory:');

const VALID_CURRENCIES = ['USD', 'EUR', 'GBP', 'JPY', 'CAD', 'AUD', 'CHF', 'CNY', 'SEK', 'NOK'];

db.exec(`
  CREATE TABLE accounts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    owner TEXT NOT NULL,
    balance INTEGER NOT NULL DEFAULT 0,
    currency TEXT NOT NULL DEFAULT 'USD'
  );
  CREATE TABLE transactions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    from_account INTEGER,
    to_account INTEGER,
    amount INTEGER NOT NULL,
    currency TEXT NOT NULL DEFAULT 'USD',
    created_at TEXT DEFAULT (datetime('now'))
  );
`);

db.prepare('INSERT INTO accounts (owner, balance, currency) VALUES (?, ?, ?)').run('Alice', 100000, 'USD');
db.prepare('INSERT INTO accounts (owner, balance, currency) VALUES (?, ?, ?)').run('Bob', 50000, 'USD');

app.get('/health', (req, res) => res.json({ status: 'ok' }));

app.get('/accounts', (req, res) => {
  const { currency } = req.query;
  const accounts = currency
    ? db.prepare('SELECT * FROM accounts WHERE currency = ?').all(currency.toUpperCase())
    : db.prepare('SELECT * FROM accounts').all();
  res.json(accounts);
});

app.post('/accounts', (req, res) => {
  const { owner, balance = 0, currency = 'USD' } = req.body;
  if (!owner) return res.status(400).json({ error: 'owner required' });
  const cur = (currency || 'USD').toUpperCase();
  if (!VALID_CURRENCIES.includes(cur)) return res.status(400).json({ error: `invalid currency: ${cur}` });
  const id = db.prepare('INSERT INTO accounts (owner, balance, currency) VALUES (?, ?, ?)').run(owner, balance, cur).lastInsertRowid;
  res.status(201).json({ id, owner, balance, currency: cur });
});

app.post('/transactions', (req, res) => {
  const { from_account, to_account, amount } = req.body;
  if (!amount || amount <= 0) return res.status(400).json({ error: 'amount must be positive' });
  const from = db.prepare('SELECT * FROM accounts WHERE id = ?').get(from_account);
  const to = db.prepare('SELECT * FROM accounts WHERE id = ?').get(to_account);
  if (!from || !to) return res.status(404).json({ error: 'account not found' });
  if (from.currency !== to.currency) return res.status(422).json({ error: `cannot transfer between ${from.currency} and ${to.currency} accounts` });
  if (from.balance < amount) return res.status(422).json({ error: 'insufficient funds' });
  db.prepare('UPDATE accounts SET balance = balance - ? WHERE id = ?').run(amount, from_account);
  db.prepare('UPDATE accounts SET balance = balance + ? WHERE id = ?').run(amount, to_account);
  const id = db.prepare('INSERT INTO transactions (from_account, to_account, amount, currency) VALUES (?, ?, ?, ?)').run(from_account, to_account, amount, from.currency).lastInsertRowid;
  res.status(201).json({ id, from_account, to_account, amount, currency: from.currency });
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
