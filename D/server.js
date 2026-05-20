'use strict';
const express = require('express');
const app = express();
app.use(express.json());

let users = [
  { id: 1, name: 'Alice',   email: 'alice@example.com',   createdAt: '2024-01-01T00:00:00Z' },
  { id: 2, name: 'Bob',     email: 'bob@example.com',     createdAt: '2024-01-15T00:00:00Z' },
  { id: 3, name: 'Charlie', email: 'charlie@example.com', createdAt: '2024-02-01T00:00:00Z' },
];
const plans = [
  { id: 'starter',    name: 'Starter',    priceUsd: 9.99,  interval: 'month' },
  { id: 'pro',        name: 'Pro',        priceUsd: 29.99, interval: 'month' },
  { id: 'enterprise', name: 'Enterprise', priceUsd: 99.99, interval: 'month' },
];
let nextUserId = 4;
let subscriptions = [];
let invoices = [];
let nextSubId = 1;
let nextInvId = 1;

app.get('/users', (_req, res) => res.json(users));
app.get('/users/:id', (req, res) => {
  const user = users.find(u => u.id === +req.params.id);
  return user ? res.json(user) : res.status(404).json({ error: 'not found' });
});
app.post('/users', (req, res) => {
  const { name, email } = req.body;
  if (!name || !email) return res.status(400).json({ error: 'name and email are required' });
  const user = { id: nextUserId++, name, email, createdAt: new Date().toISOString() };
  users.push(user);
  res.status(201).json(user);
});
app.delete('/users/:id', (req, res) => {
  users = users.filter(u => u.id !== +req.params.id);
  res.status(204).send();
});
app.get('/plans', (_req, res) => res.json(plans));

// Subscriptions
app.post('/subscriptions', (req, res) => {
  const { userId, planId } = req.body;
  const user = users.find(u => u.id === userId);
  if (!user) return res.status(404).json({ error: 'user not found' });
  const plan = plans.find(p => p.id === planId);
  if (!plan) return res.status(404).json({ error: 'plan not found' });
  const existing = subscriptions.find(s => s.userId === userId && s.status === 'active');
  if (existing) return res.status(409).json({ error: 'already subscribed' });
  const sub = { id: nextSubId++, userId, planId, status: 'active', startedAt: new Date().toISOString(), cancelledAt: null };
  subscriptions.push(sub);
  res.status(201).json(sub);
});
app.get('/subscriptions/:userId', (req, res) => {
  const sub = subscriptions.find(s => s.userId === +req.params.userId);
  if (!sub) return res.status(404).json({ error: 'not found' });
  res.json(sub);
});
app.delete('/subscriptions/:userId', (req, res) => {
  const sub = subscriptions.find(s => s.userId === +req.params.userId && s.status === 'active');
  if (!sub) return res.status(404).json({ error: 'no active subscription' });
  sub.status = 'cancelled';
  sub.cancelledAt = new Date().toISOString();
  res.status(200).json(sub);
});

// Invoices
app.post('/invoices/generate/:userId', (req, res) => {
  const userId = +req.params.userId;
  const sub = subscriptions.find(s => s.userId === userId && s.status === 'active');
  if (!sub) return res.status(404).json({ error: 'no active subscription' });
  const plan = plans.find(p => p.id === sub.planId);
  const subtotal = plan.priceUsd;
  const tax = Math.round(subtotal * 0.1 * 100) / 100;
  const total = Math.round((subtotal + tax) * 100) / 100;
  const inv = {
    id: nextInvId++, userId, subscriptionId: sub.id,
    lineItems: [{ description: `${plan.name} plan (monthly)`, amount: subtotal }],
    subtotal, tax, total, currency: 'USD',
    createdAt: new Date().toISOString(),
  };
  invoices.push(inv);
  res.status(201).json(inv);
});
app.get('/invoices/:userId', (req, res) => {
  const userId = +req.params.userId;
  const userInvoices = invoices.filter(i => i.userId === userId)
    .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
  res.json(userInvoices);
});

const PORT = process.env.PORT || 3001;
const server = app.listen(PORT, () => console.log(`[billing-app] listening on port ${PORT}`));
module.exports = { app, server };
