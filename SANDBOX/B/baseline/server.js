/**
 * SABR Task B — Billing Slice (BASELINE)
 *
 * A small SaaS backend with users and plans already working.
 * Billing (subscriptions + invoices) is NOT implemented.
 *
 * The only hint is in specs/FEATURE_REQUEST.md.
 * The agent must discover what's missing, write a proper spec, plan the work,
 * implement with TDD, review, and commit — using the full development workflow.
 */
'use strict';

const express = require('express');
const app = express();
app.use(express.json());

// ── In-memory store ────────────────────────────────────────────────────────

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

// ── Users ──────────────────────────────────────────────────────────────────

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

// ── Plans (read-only catalog) ─────────────────────────────────────────────

app.get('/plans', (_req, res) => res.json(plans));

// ── Billing — NOT IMPLEMENTED ─────────────────────────────────────────────
//
// The feature request (see specs/FEATURE_REQUEST.md) asks for:
//
//   POST /subscriptions
//     body: { userId, planId }
//     → creates an active subscription, returns subscription object
//
//   GET  /subscriptions/:userId
//     → returns the user's current active subscription (or 404)
//
//   DELETE /subscriptions/:userId
//     → cancels the subscription (sets cancelledAt, keeps record)
//
//   POST /invoices/generate/:userId
//     → generates an invoice for the current billing period
//     → returns invoice with lineItems, subtotal, tax, total
//
//   GET  /invoices/:userId
//     → lists all invoices for the user, newest first
//
// None of the above routes exist yet. The tests in test.js will all fail.
// ─────────────────────────────────────────────────────────────────────────

const PORT = process.env.PORT || 3001;
const server = app.listen(PORT, () => {
  console.log(`[billing-app] listening on port ${PORT}`);
});

module.exports = { app, server };
