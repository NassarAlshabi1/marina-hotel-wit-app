// ═══════════════════════════════════════════════════════════════
//  finance-routes.ts — نقاط API التمويل على D1 الحية
//
//  كل الأدوار تقرأ (forecast / kpi) — الاعتماد والمقارنة إداريان
//  (admin | manager) لأنهما إجراء حوكمة أسبوعي (خطوات §8).
//
//  GET  /api/finance/forecast?scenario=base|conservative|stress
//         &revenue=1.0&collection=1.0&start=YYYY-MM-DD&weeks=13&coverage=4
//  GET  /api/finance/kpi
//  GET  /api/finance/snapshots                    (admin|manager)
//  POST /api/finance/snapshots {label?, scenario?, start?,
//         weeks?, coverage?}                      (admin|manager)
//  GET  /api/finance/variance?snapshot_id=N       (admin|manager)
//
//  ملاحظة التصميم: الحساب كله خادمي على D1 الحية ليكون النموذج موحداً
//  عبر الأجهزة (مصدر حقيقة واحد) — العميل يعرض النتيجة فقط ويمكنه
//  تمرير معاملات السيناريو المحلية كتجربة ما-لو دون المساس بالخادم.
// ═══════════════════════════════════════════════════════════════

import {
  SCENARIOS,
  analyzePaymentProfile,
  buildForecast,
  computeKpi,
  computeVariance,
  dayStart,
  parseDate,
  toDayKey,
  type ForecastResult,
  type ScenarioParams,
} from './finance';
import {
  getFinanceSnapshot,
  listFinanceSnapshots,
  loadFinanceInput,
  saveFinanceSnapshot,
} from './finance-data';

export interface AuthContextLike {
  userId: string;
  username: string;
  role: string;
}

interface FinanceEnvLike {
  CORS_ORIGIN: string;
}

function json(data: unknown, status = 200, origin = '*'): Response {
  const headers = new Headers({ 'Content-Type': 'application/json' });
  headers.set('Access-Control-Allow-Origin', origin);
  return new Response(JSON.stringify(data), { status, headers });
}

function parseScenario(
  url: URL
): { scenario: ScenarioParams; custom: boolean } {
  const key = (url.searchParams.get('scenario') ?? 'base').trim().toLowerCase();
  const base = SCENARIOS[key] ?? SCENARIOS.base;
  const revenue = url.searchParams.get('revenue');
  const collection = url.searchParams.get('collection');
  if (revenue == null && collection == null) {
    return { scenario: base, custom: false };
  }
  const rv = revenue == null ? base.revenueFactor : Number(revenue);
  const cl = collection == null ? base.collectionFactor : Number(collection);
  const okRv = Number.isFinite(rv) && rv > 0 && rv <= 3 ? rv : base.revenueFactor;
  const okCl =
    Number.isFinite(cl) && cl > 0 && cl <= 3 ? cl : base.collectionFactor;
  return {
    scenario: { ...base, revenueFactor: okRv, collectionFactor: okCl },
    custom: okRv !== base.revenueFactor || okCl !== base.collectionFactor,
  };
}

function parseIntParam(
  url: URL,
  name: string,
  def: number,
  min: number,
  max: number
): number {
  const raw = url.searchParams.get(name);
  if (raw == null || raw.trim() === '') return def;
  const n = Number(raw);
  if (!Number.isFinite(n)) return def;
  return Math.min(max, Math.max(min, Math.round(n)));
}

/** ينتهي نموذج الـ13 أسبوعاً ببدايته + 13×7 أيام − 1. */
function modelEndKey(startKey: string, weeksCount: number): string {
  const s = parseDate(startKey);
  if (!s) return startKey;
  return toDayKey(new Date(dayStart(s).getTime() + weeksCount * 7 * 86_400_000 - 86_400_000));
}

async function buildLiveForecast(
  db: D1Database,
  scenario: ScenarioParams,
  opts: { forecastStart?: Date; weeksCount: number; coverageTargetWeeks: number }
): Promise<ForecastResult> {
  const input = await loadFinanceInput(db);
  const now = new Date();
  const profile = analyzePaymentProfile(input, now);
  return buildForecast(input, scenario, profile, now, {
    forecastStart: opts.forecastStart,
    weeksCount: opts.weeksCount,
    coverageTargetWeeks: opts.coverageTargetWeeks,
  });
}

/**
 * معالج نقاط /api/finance/* — يستدعى من index.ts بعد بوابة المصادقة
 * وضمن نطاق المسار نفسه؛ يعيد Response جاهزاً.
 */
export async function handleFinanceRequest(
  request: Request,
  db: D1Database,
  ctx: AuthContextLike,
  url: URL,
  env: FinanceEnvLike
): Promise<Response> {
  const path = url.pathname;
  const method = request.method;
  const origin = env.CORS_ORIGIN || '*';
  const isPrivileged = ctx.role === 'admin' || ctx.role === 'manager';

  try {
    // ─── نموذج الـ13 أسبوعاً ──────────────────────────────────
    if (path === '/api/finance/forecast' && method === 'GET') {
      const { scenario } = parseScenario(url);
      const weeksCount = parseIntParam(url, 'weeks', 13, 1, 26);
      const coverage = parseIntParam(url, 'coverage', 4, 1, 12);
      const startRaw = url.searchParams.get('start');
      const startDate = startRaw ? parseDate(startRaw) : null;
      const result = await buildLiveForecast(db, scenario, {
        forecastStart: startDate ? dayStart(startDate) : undefined,
        weeksCount,
        coverageTargetWeeks: coverage,
      });
      return json({ source: 'd1', ...result }, 200, origin);
    }

    // ─── لوحة المؤشرات الأسبوعية ──────────────────────────────
    if (path === '/api/finance/kpi' && method === 'GET') {
      const input = await loadFinanceInput(db);
      const now = new Date();

      // نسبة التدفق المؤكد للأسبوع الأول من السيناريو الأساسي
      let confirmedRatio: number | null = null;
      try {
        const input2 = input; // نفس المدخل — لا إعادة تحميل
        const profile = analyzePaymentProfile(input2, now);
        const base = buildForecast(input2, SCENARIOS.base, profile, now, {});
        if (base.weeks.length > 0) {
          const w1 = base.weeks[0].inflow;
          const total = w1.confirmed + w1.probable + w1.estimated;
          confirmedRatio = total > 0 ? w1.confirmed / total : 0;
        }
      } catch {
        confirmedRatio = null;
      }

      const result = computeKpi(input, now, confirmedRatio);
      return json({ source: 'd1', ...result }, 200, origin);
    }

    // ─── قائمة اللقطات المعتمدة ────────────────────────────────
    if (path === '/api/finance/snapshots' && method === 'GET') {
      if (!isPrivileged) {
        return json({ error: 'Manager or admin role required' }, 403, origin);
      }
      const limit = parseIntParam(url, 'limit', 26, 1, 100);
      const snapshots = await listFinanceSnapshots(db, limit);
      return json({ snapshots, count: snapshots.length }, 200, origin);
    }

    // ─── اعتماد نسخة أسبوعية (خطوة §8.7) ──────────────────────
    if (path === '/api/finance/snapshots' && method === 'POST') {
      if (!isPrivileged) {
        return json({ error: 'Manager or admin role required' }, 403, origin);
      }
      let body: Record<string, unknown> = {};
      try {
        body = (await request.json()) as Record<string, unknown>;
      } catch {
        body = {};
      }
      const scenarioKeyRaw =
        typeof body['scenario'] === 'string' ? body['scenario'] : 'base';
      const scenario =
        SCENARIOS[scenarioKeyRaw.trim().toLowerCase()] ?? SCENARIOS.base;
      const weeksCount =
        typeof body['weeks'] === 'number' && Number.isFinite(body['weeks'])
          ? Math.min(26, Math.max(1, Math.round(body['weeks'] as number)))
          : 13;
      const coverage =
        typeof body['coverage'] === 'number' && Number.isFinite(body['coverage'])
          ? Math.min(12, Math.max(1, Math.round(body['coverage'] as number)))
          : 4;
      const startRaw = typeof body['start'] === 'string' ? body['start'] : null;
      const startDate = startRaw ? parseDate(startRaw) : null;

      const forecast = await buildLiveForecast(db, scenario, {
        forecastStart: startDate ? dayStart(startDate) : undefined,
        weeksCount,
        coverageTargetWeeks: coverage,
      });

      const labelRaw =
        typeof body['label'] === 'string' && body['label'].trim()
          ? body['label'].trim().slice(0, 120)
          : `أسبوع ${forecast.start}`;
      const lastWeek = forecast.weeks[forecast.weeks.length - 1];

      const saved = await saveFinanceSnapshot(db, {
        label: labelRaw,
        scenarioKey: scenario.key,
        scenarioJson: JSON.stringify(scenario),
        modelStart: forecast.start,
        modelEnd: lastWeek ? lastWeek.end : forecast.start,
        openingBalance: forecast.openingBalance,
        totalInflow: forecast.totalInflow,
        totalOutflow: forecast.totalOutflow,
        financingNeed: forecast.financingNeed,
        weeksBelowThreshold: forecast.weeksBelowThreshold,
        forecastJson: JSON.stringify(forecast),
        approvedBy: ctx.username || ctx.userId,
      });

      return json({ snapshot: { ...saved, forecast_json: undefined } }, 201, origin);
    }

    // ─── الفعلي مقابل المتوقع (خطوة §8.9) ─────────────────────
    const varianceMatch = /^\/api\/finance\/variance$/.test(path);
    if (varianceMatch && method === 'GET') {
      if (!isPrivileged) {
        return json({ error: 'Manager or admin role required' }, 403, origin);
      }
      const snapshotId = parseIntParam(url, 'snapshot_id', 0, 0, 2_147_483_647);
      if (snapshotId <= 0) {
        return json({ error: 'snapshot_id is required' }, 400, origin);
      }
      const snap = await getFinanceSnapshot(db, snapshotId);
      if (!snap) {
        return json({ error: 'Snapshot not found' }, 404, origin);
      }
      let forecast: ForecastResult;
      try {
        forecast = JSON.parse(snap.forecast_json) as ForecastResult;
      } catch {
        return json({ error: 'Snapshot forecast payload corrupt' }, 500, origin);
      }
      const input = await loadFinanceInput(db);
      const result = computeVariance(
        snap.id,
        snap.label,
        new Date(snap.approved_at).toISOString(),
        forecast,
        input,
        new Date()
      );
      return json({ source: 'd1', ...result }, 200, origin);
    }

    return json({ error: 'Not found', path }, 404, origin);
  } catch (err) {
    console.error('[FINANCE]', method, path, err);
    return json(
      { error: 'Finance computation failed', detail: String(err) },
      500,
      origin
    );
  }
}
