/**
 * Worker configuration & constants.
 * Mirrors `mobile/lib/services/appwrite_config.dart` (`_entityToCollection`).
 */

/** The 21 entities the sync engine owns (matches Appwrite collections). */
export const SYNC_ENTITIES = [
  'rooms',
  'bookings',
  'payments',
  'expenses',
  'employees',
  'debts',
  'booking_notes',
  'shift_notes',
  'cash_transactions',
  'booking_nights',
  'salary_cycles',
  'salary_payments',
  'salary_withdrawals',
  'salary_carry_over_logs',
  'blacklist',
  'price_adjustments',
  'booking_price_adjustments',
  'payment_voids',
  'guest_infos',
  'app_settings',
] as const;

export type SyncEntity = (typeof SYNC_ENTITIES)[number];

/** Entities excluded from sync entirely (audit_logs is local-only). */
export const EXCLUDED_FROM_SYNC = ['audit_logs'] as const;

/** Per-entity pull limits (mirrors `SyncConstants.initialBookingNightsPullLimit`). */
export const INITIAL_PULL_LIMITS: Record<string, number> = {
  booking_nights: 1000,
};

export const DEFAULT_INITIAL_PULL_LIMIT = 1000;

/** Rate limiting (token bucket). */
export const RATE_LIMIT = {
  DEFAULT: 60, // req / minute / device
  PULL_METADATA: 120,
  ADMIN: 1000,
  WINDOW_MS: 60_000,
};

/** Pull throttle (mirrors the 2-minute central throttle). */
export const PULL_THROTTLE_MS = 120_000;

/** Pull staleness guard: delta-only after this idle. */
export const PULL_STALENESS_MS = 60 * 60 * 1000;

/** Durable Object lock TTL for a sync cycle. */
export const SYNC_LOCK_TTL_MS = 30_000;

/** JWT config. */
export const JWT = {
  ISS: 'marina-sync-worker',
  AUD: 'marina-hotel-mobile',
  EXPIRES_IN: '12h',
};