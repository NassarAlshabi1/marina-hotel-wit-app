// ═══════════════════════════════════════════════════════════════
//  sync.push.booking_nights.test.ts — «لا ليالٍ مكررة» على D1
//
//  يثبّت عقد الهوية الجديد (تقرير 2026-11-23 / الإصلاحات):
//   1. هوية الليلة تُترجم من uuid الحجز إلى معرّف الحجز الخادمي، ولا
//      يُحفظ booking_local_id الخاص بجهاز المرسل (تصادم 115 معرّفاً).
//   2. لا يمكن أن يوجد صفّان حيّان لنفس (الحجز، اليوم): الإدراج الجديد
//      يُخفي القديم في نفس الدفعة الذرّية.
//   3. ليلة بلا hotel_day_key أو بلا حجز قابل للحل لا تُنشأ (لا يتامى 0/'').
//   4. حمولة تحديث رقيقة (عميل أقدم) ترث الهوية من الصف القائم بدل الفشل.
// ═══════════════════════════════════════════════════════════════

import { env } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import {
  adminAuthHeader,
  pushOp,
  pushOperations,
  resetDb,
  uniqueUuid,
  type PushResponseBody,
} from './helpers';

const DAY = '2026-11-20';

beforeEach(async () => {
  await resetDb();
});

function bookingPayload(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    local_uuid: uniqueUuid('booking'),
    room_number: `N${Math.floor(Math.random() * 1_000_000)}`,
    guest_name: 'ضيف اختبار',
    guest_phone: '0500000000',
    guest_nationality: 'يمني',
    checkin_date: `${DAY}T14:00:00.000Z`,
    checkout_date: '2026-11-23T12:00:00.000Z',
    status: 'active',
    created_at: 1700000000,
    updated_at: 1700000000,
    last_modified: 1700000000,
    version: 1,
    origin: 'local',
    vector_clock: '{}',
    device_id: 'device-A',
    ...overrides,
  };
}

function nightPayload(bookingUuid: string, overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    local_uuid: uniqueUuid('night'),
    // معرّف جهاز آخر — يجب ألا يُحفظ كما هو على D1
    booking_local_id: 999,
    booking_uuid_cache: bookingUuid,
    hotel_day_key: DAY,
    night_start: `${DAY}T14:00:00.000Z`,
    night_end: '2026-11-21T12:00:00.000Z',
    nightly_rate: 100,
    base_rate: 100,
    adjustment: 0,
    final_rate: 100,
    sequence: 1,
    is_processed_by_auto_fix: 0,
    created_at: 1700000000,
    updated_at: 1700000000,
    last_modified: 1700000000,
    created_at_epoch: 0,
    last_modified_epoch: 0,
    version: 1,
    origin: 'derived',
    vector_clock: '{}',
    device_id: 'device-A',
    ...overrides,
  };
}

async function createBooking(auth: string) {
  const payload = bookingPayload();
  const res = await pushOperations(auth, [pushOp('bookings', 'create', payload)]);
  const body = (await res.json()) as PushResponseBody;
  expect(body.summary.success).toBe(1);
  const row = await env.DB.prepare('SELECT id, local_uuid FROM bookings WHERE local_uuid = ?')
    .bind(payload.local_uuid as string)
    .first<{ id: number; local_uuid: string }>();
  expect(row).not.toBeNull();
  return { uuid: payload.local_uuid as string, serverId: row!.id };
}

async function liveNights() {
  const rows = await env.DB.prepare(
    'SELECT id, local_uuid, booking_local_id, hotel_day_key, booking_uuid_cache FROM booking_nights WHERE deleted_at IS NULL ORDER BY id'
  ).all<{
    id: number;
    local_uuid: string;
    booking_local_id: number;
    hotel_day_key: string;
    booking_uuid_cache: string | null;
  }>();
  return rows.results;
}

describe('push booking_nights: identity + no duplicates', () => {
  it('translates booking_local_id from the booking uuid (never stores another device id)', async () => {
    const auth = await adminAuthHeader();
    const booking = await createBooking(auth);

    const night = nightPayload(booking.uuid);
    const res = await pushOperations(auth, [pushOp('booking_nights', 'create', night)]);
    const body = (await res.json()) as PushResponseBody;
    expect(body.summary.success).toBe(1);

    const rows = await liveNights();
    expect(rows).toHaveLength(1);
    expect(rows[0].booking_local_id).toBe(booking.serverId);
    expect(rows[0].booking_uuid_cache).toBe(booking.uuid);
    expect(rows[0].hotel_day_key).toBe(DAY);
    expect(rows[0].local_uuid).toBe(night.local_uuid as string);
  });

  it('collapses a second live night for the same (booking, day) into one live row', async () => {
    const auth = await adminAuthHeader();
    const booking = await createBooking(auth);

    const first = nightPayload(booking.uuid);
    const second = nightPayload(booking.uuid, { final_rate: 120, nightly_rate: 120 });
    const res = await pushOperations(auth, [
      pushOp('booking_nights', 'create', first),
      pushOp('booking_nights', 'create', second),
    ]);
    const body = (await res.json()) as PushResponseBody;
    expect(body.summary.success).toBe(2);

    const live = await liveNights();
    expect(live).toHaveLength(1);
    expect(live[0].local_uuid).toBe(second.local_uuid as string);

    const all = await env.DB.prepare(
      'SELECT COUNT(*) AS c FROM booking_nights'
    ).first<{ c: number }>();
    expect(all?.c).toBe(2); // القديم محفوظ كأثر (tombstone) لا محذوفاً
    const hidden = await env.DB.prepare(
      'SELECT COUNT(*) AS c FROM booking_nights WHERE deleted_at IS NOT NULL'
    ).first<{ c: number }>();
    expect(hidden?.c).toBe(1);
  });

  it('rejects a night without hotel_day_key instead of creating an orphan row', async () => {
    const auth = await adminAuthHeader();
    const booking = await createBooking(auth);

    const broken = nightPayload(booking.uuid, { hotel_day_key: '', night_start: '' });
    const res = await pushOperations(auth, [pushOp('booking_nights', 'create', broken)]);
    const body = (await res.json()) as PushResponseBody;
    expect(body.summary.failed).toBe(1);
    expect(body.results[0].error).toContain('hotel_day_key');
    expect(await liveNights()).toHaveLength(0);
  });

  it('rejects a night whose booking uuid cannot be resolved (no 0/"" orphan)', async () => {
    const auth = await adminAuthHeader();
    const res = await pushOperations(auth, [
      pushOp(
        'booking_nights',
        'create',
        nightPayload(uniqueUuid('ghost-booking'), { booking_local_id: 0 })
      ),
    ]);
    const body = (await res.json()) as PushResponseBody;
    expect(body.summary.failed).toBe(1);
    expect(await liveNights()).toHaveLength(0);
  });

  it('lets a thin update payload inherit identity from the existing row', async () => {
    const auth = await adminAuthHeader();
    const booking = await createBooking(auth);

    const night = nightPayload(booking.uuid);
    await pushOperations(auth, [pushOp('booking_nights', 'create', night)]);

    const res = await pushOperations(auth, [
      pushOp('booking_nights', 'update', {
        local_uuid: night.local_uuid,
        final_rate: 130,
      }),
    ]);
    const body = (await res.json()) as PushResponseBody;
    expect(body.summary.success).toBe(1);

    const rows = await liveNights();
    expect(rows).toHaveLength(1);
    expect(rows[0].hotel_day_key).toBe(DAY);
    expect(rows[0].booking_local_id).toBe(booking.serverId);
    expect(rows[0].booking_uuid_cache).toBe(booking.uuid);
  });

  it('never creates a row from an update of an unknown thin payload', async () => {
    const auth = await adminAuthHeader();
    const res = await pushOperations(auth, [
      pushOp('booking_nights', 'update', { local_uuid: uniqueUuid('ghost-night') }),
    ]);
    const body = (await res.json()) as PushResponseBody;
    expect(body.summary.failed).toBe(1);
    expect(await liveNights()).toHaveLength(0);
  });
});
