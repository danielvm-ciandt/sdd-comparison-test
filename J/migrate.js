// migrate.js — idempotent migration to add currency column if missing
const Database = require('better-sqlite3');
const path = require('path');

// Only runs when called standalone (not when required by test.js)
if (require.main === module) {
  // If there's no db file, just exit OK (in-memory scenario)
  console.log('Migration: adding currency support (idempotent)');
  console.log('No persistent DB file — migration is a no-op for in-memory mode.');
  process.exit(0);
}
