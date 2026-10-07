// ═══════════════════════════════════════════════════════════════
//  sync.tombstone.sweep.test.ts
//
//  عقد مسح الحذفيات التاريخي (tombstones_only=1) — الفرضيات التي
//  يعتمد عليها **تطبيق أندرويد** في
//  `SyncManager.sweepHistoricalTombstones`:
//
//   1. الصفحة تُعاد بمؤشر = updated_at لآخر صف مُعاد **فعلاً**، لا أكبر
//      طابع في الجداول — وإلا قفز مؤشر المسح فوق حذفيات لم تُسلَّم.
//   2. `has_more` يعني «بقي حذفيات بعد هذا المؤشر» والمؤشر محفوظ بعد كل
//      صفحة يستأنف بدقة بلا تكرار ولا فقد.
//   3. `exclude_device` يُطبَّق داخل وضع الحذفيات: حذفيات الجهاز نفسه لا
//      تُعاد إليه (طبّقها محلياً أصلاً) — نظير `exclude_device: ownDevice`
//      في `_sweepHistoricalTombstones` بـ Dart.
//   4. الصفوف الحية لا تظهر إطلاقاً في هذه النافذة (ولا تُحرّك مؤشرها).
//
//  نظير Dart: mobile/lib/services/cloudflare_sync_manager.dart
//  l.3661-3700، ونظير Kotlin: SyncManager.kt (performTombstoneSweepIfDue).
// ═══════════════════════════════════════════════════════════════

import { env } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import {
  resetDb,
  adminAuthHeader,
  pull,
  pushOp,
  pushOperations,
  roomPayload,
  type PushResponseBody,
} from './helpers';

beforeEach(async () => {
  await resetDb();
});

/** يحوّل صفاً إلى tombstone بطابع زمني محدد (يحاكي deleteRecord الخادمي). */
async function markDeleted(localUuid: string, stamp: number): Promise<void> {
  await env.DB.prepare(
    'UPDATE rooms SET deleted_at = ?, updated_at = ? WHERE local_uuid = ?',
  )
    .bind(stamp, stamp, localUuid)
    .run();
}

async function pushLive(device: string): Promise<string> {
  const auth = await adminAuthHeader();
  const payload = roomPayload({ device_id: device });
  const res = await pushOperations(auth, [pushOp('rooms', 'create', payload)]);
  const body = (await res.json()) as PushResponseBody;
  expect(body.summary.failed).toBe(0);
  return payload.local_uuid as string;
}

describe('pull: convergence sweep contract (tombstones_only=1)', () => {
  it('paginates by returned cursor only — newer live rows never push the sweep cursor forward', async () => {
    const auth = await adminAuthHeader();
    const older = await pushLive('device-A');
    const newer = await pushLive('device-B');
    const survivor = await pushLive('device-C'); // صف حي يبقى حياً
    await markDeleted(older, 1_700_000_100);
    await markDeleted(newer, 1_700_000_200);

    // الصف الحي الثالث يحمل طابعاً أحدث (المخصص الخادمي) — الفخ: أي تنفيذ
    // يعيد «أكبر طابع» كمؤشر سيقفز فوق حذفيات لم تُسلّم.
    const seen: string[] = [];
    const cursors: number[] = [];
    let cursor = '0';

    for (let page = 0; page < 10; page++) {
      const data = await pull(auth, {
        cursor,
        limit: '1',
        tombstones_only: '1',
        exclude_device: 'device-Z', // لا يستبعد شيئاً من الصفوف أعلاه
      });
      const changes = data.changes as Array<Record<string, unknown>>;
      expect(changes.length).toBeLessThanOrEqual(1);
      for (const row of changes) {
        // كل ما يُعاد في هذه النافذة حذف — ولا صف حي أبداً.
        expect(row['deleted_at']).not.toBeNull();
        expect(row['local_uuid']).not.toBe(survivor);
        seen.push(row['local_uuid'] as string);
        // المؤشر = طابع آخر صف مُعاد بالضبط (لا أكبر طابع في الجداول).
        expect(Number(data.cursor)).toBe(Number(row['updated_at']));
      }
      cursors.push(Number(data.cursor));
      cursor = data.cursor;
      if (!data.has_more) break;
    }

    // الحذفيان مرّا مرة واحدة بالضبط، بترتيب زمني، والمؤشر تصاعدي.
    expect(seen).toEqual([older, newer]);
    expect(cursors).toEqual([1_700_000_100, 1_700_000_200]);
    // الصف الحي يحمل طابعاً أحدث من كل حذفية، ومع ذلك انتهى مؤشر المسح عند
    // آخر حذفية مُسلَّمة — لم يقفز فوق أي حذفية.
    const survivorRow = await env.DB.prepare(
      'SELECT updated_at FROM rooms WHERE local_uuid = ?',
    )
      .bind(survivor)
      .first<{ updated_at: number }>();
    expect(Number(survivorRow?.updated_at)).toBeGreaterThan(1_700_000_200);
    expect(Number(cursor)).toBe(1_700_000_200);
    // الصف الحي لم يُسلَّم في نافذة الحذفيات إطلاقاً.
    expect(seen).not.toContain(survivor);
  });

  it('exclude_device drops the sweeping device own tombstones', async () => {
    const auth = await adminAuthHeader();
    const mine = await pushLive('device-A');
    const theirs = await pushLive('device-B');
    await markDeleted(mine, 1_700_000_100);
    await markDeleted(theirs, 1_700_000_200);

    const scoped = await pull(auth, {
      cursor: '0',
      limit: '200',
      tombstones_only: '1',
      exclude_device: 'device-A',
    });
    const scopedUuids = (scoped.changes as Array<Record<string, unknown>>).map(
      (row) => row['local_uuid'],
    );
    expect(scopedUuids).toContain(theirs);
    expect(scopedUuids).not.toContain(mine);

    // بلا استبعاد: كلاهما يُعاد (نفس النافذة، نفس المؤشر).
    const unscoped = await pull(auth, {
      cursor: '0',
      limit: '200',
      tombstones_only: '1',
    });
    const unscopedUuids = (unscoped.changes as Array<Record<string, unknown>>).map(
      (row) => row['local_uuid'],
    );
    expect(unscopedUuids).toContain(mine);
    expect(unscopedUuids).toContain(theirs);
  });

  it('re-requesting the saved sweep cursor is idempotent (crash resume) and the window then closes', async () => {
    const auth = await adminAuthHeader();
    const only = await pushLive('device-B');
    await markDeleted(only, 1_700_000_100);

    const first = await pull(auth, { cursor: '0', limit: '50', tombstones_only: '1' });
    expect((first.changes as Array<Record<string, unknown>>).length).toBe(1);
    expect(first.has_more).toBe(false);

    // إعادة الطلب بنفس المؤشر المحفوظ (سيناريو انهيار بعد حفظ المؤشر قبل
    // إغلاق العلم): لا تكرار، ولا تقدم، ورسالة «انتهى» واضحة.
    const replay = await pull(auth, {
      cursor: first.cursor,
      limit: '50',
      tombstones_only: '1',
    });
    expect((replay.changes as Array<Record<string, unknown>>).length).toBe(0);
    expect(replay.has_more).toBe(false);
    expect(Number(replay.cursor)).toBe(Number(first.cursor));
  });
});
