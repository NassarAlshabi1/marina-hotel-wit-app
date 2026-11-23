// ═══════════════════════════════════════════════════════════════
//  sync.push.booking_price_adjustments.test.ts
//
//  عقد 2026-11-23: تسوية السعر تحمل «يوم سريان» واحداً بثلاثة أسماء
//  (effective_hotel_day القانوني، وhotel_day_key/applied_date القديمان)
//  وكلها متزامنة عند الكتابة؛ وهوية الحجز العالمية (booking_uuid /
//  booking_local_uuid) تُترجم إلى معرّف الحجز الخادمي.
//
//  الجذر الذي يمنعه الاختبار: فلترة الأعمدة في worker تُسقط أي اسم ليس
//  عموداً، فتصل التسوية بلا يوم فتُستبعد من حساب الليلة، أو بلا هوية
//  حجز فتُطبَّق على حجز آخر بنفس رقم الجهاز.
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

async function createBooking(auth: string): Promise<{ uuid: string; serverId: number }> {
  const payload = {
    local_uuid: uniqueUuid('booking'),
    room_number: `P${Math.floor(Math.random() * 1_000_000)}`,
    guest_name: 'ضيف تسوية',
    guest_phone: '0500000003',
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
  };
  const res = await pushOperations(auth, [pushOp('bookings', 'create', payload)]);
  const body = (await res.json()) as PushResponseBody;
  expect(body.summary.success).toBe(1);
  const row = await env.DB.prepare('SELECT id FROM bookings WHERE local_uuid = ?')
    .bind(payload.local_uuid)
    .first<{ id: number }>();
  return { uuid: payload.local_uuid as string, serverId: row!.id };
}

function adjustmentPayload(
  bookingUuid: string,
  overrides: Record<string, unknown> = {}
): Record<string, unknown> {
  return {
    local_uuid: uniqueUuid('bpa'),
    booking_local_uuid: bookingUuid,
    booking_local_id: 999, // رقم جهاز آخر — يجب ألا يُحفظ كما هو
    room_number: 'P1',
    adjustment_type: 1,
    adjustment_mode: 'per_night',
    amount: -50,
    effective_hotel_day: DAY,
    is_active: 1,
    reason: 'discount',
    applied_by: 'device-A',
    applied_at: 1700000500,
    booking_uuid: bookingUuid,
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

async function rowOf(localUuid: string) {
  return env.DB.prepare(
    `SELECT booking_local_id, booking_local_uuid, booking_uuid,
            effective_hotel_day, hotel_day_key, applied_date, applied_at, amount
       FROM booking_price_adjustments WHERE local_uuid = ?`
  )
    .bind(localUuid)
    .first<Record<string, unknown>>();
}

describe('push booking_price_adjustments: one day, one booking identity', () => {
  it('persists all three day names and links the booking to its server id', async () => {
    const auth = await adminAuthHeader();
    const booking = await createBooking(auth);

    const payload = adjustmentPayload(booking.uuid);
    const res = await pushOperations(auth, [
      pushOp('booking_price_adjustments', 'create', payload),
    ]);
    const body = (await res.json()) as PushResponseBody;
    expect(body.summary.success).toBe(1);

    const row = await rowOf(payload.local_uuid as string);
    expect(row?.effective_hotel_day).toBe(DAY);
    expect(row?.hotel_day_key).toBe(DAY);
    expect(row?.applied_date).toBe(DAY);
    expect(row?.booking_local_id).toBe(booking.serverId);
    expect(row?.booking_local_uuid).toBe(booking.uuid);
    expect(row?.booking_uuid).toBe(booking.uuid);
    expect(row?.applied_at).toBe(1700000500);
  });

  it('accepts a legacy client that only sends applied_date', async () => {
    const auth = await adminAuthHeader();
    const booking = await createBooking(auth);

    const payload = adjustmentPayload(booking.uuid, {
      effective_hotel_day: undefined,
      hotel_day_key: undefined,
      applied_date: DAY,
    });
    const res = await pushOperations(auth, [
      pushOp('booking_price_adjustments', 'create', payload),
    ]);
    const body = (await res.json()) as PushResponseBody;
    expect(body.summary.success).toBe(1);

    const row = await rowOf(payload.local_uuid as string);
    // كان هذا الصف يصل بلا يوم فتُستبعد التسوية من حساب الليلة.
    expect(row?.effective_hotel_day).toBe(DAY);
    expect(row?.hotel_day_key).toBe(DAY);
    expect(row?.applied_date).toBe(DAY);
  });

  it('keeps the global booking identity when the booking is not on D1 yet', async () => {
    const auth = await adminAuthHeader();
    const ghost = uniqueUuid('ghost-booking');

    const payload = adjustmentPayload(ghost);
    const res = await pushOperations(auth, [
      pushOp('booking_price_adjustments', 'create', payload),
    ]);
    const body = (await res.json()) as PushResponseBody;
    // لا فشل: الهوية العالمية تُحفظ ليحلّها السحب لاحقاً
    expect(body.summary.success).toBe(1);

    const row = await rowOf(payload.local_uuid as string);
    expect(row?.booking_local_uuid).toBe(ghost);
    expect(row?.effective_hotel_day).toBe(DAY);
  });
});
