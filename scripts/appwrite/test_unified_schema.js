'use strict';

const assert = require('node:assert/strict');
const {
  SCHEMA,
  COLLECTION_INDEXES,
} = require('./unified_appwrite_setup');

const requiredCollections = [
  'rooms',
  'bookings',
  'payments',
  'expenses',
  'debts',
  'employees',
  'booking_notes',
  'booking_nights',
  'cash_transactions',
  'salary_cycles',
  'salary_payments',
  'salary_withdrawals',
  'salary_carry_over_logs',
  'shift_notes',
  'price_adjustments',
  'booking_price_adjustments',
  'audit_logs',
  'payment_voids',
  'guest_infos',
  'blacklist',
  'app_settings',
  'app_users',
  'devices',
  'sync_logs',
];

for (const collection of requiredCollections) {
  assert.ok(SCHEMA[collection], `Missing required collection: ${collection}`);
}

for (const [collection, indexes] of Object.entries(COLLECTION_INDEXES)) {
  assert.ok(SCHEMA[collection], `Indexes declared for unknown collection: ${collection}`);
  for (const index of indexes) {
    for (const field of index.attributes) {
      assert.ok(
        Object.hasOwn(SCHEMA[collection], field),
        `Index ${collection}.${index.key} references missing field ${field}`,
      );
    }
  }
}

console.log(
  `✅ Unified schema verified: ${Object.keys(SCHEMA).length} collections, ` +
    `${Object.values(COLLECTION_INDEXES).flat().length} business indexes.`,
);
