/**
 * Conflict resolution — vector clock + optimistic lock + tombstone precedence.
 * Mirrors `mobile/lib/services/sync_core/smart_conflict_resolver.dart`.
 */

/** Merge two vector clocks; the result is the element-wise max. */
export function mergeVectorClocks(
  a: Record<string, number> | string,
  b: Record<string, number> | string,
): Record<string, number> {
  const parse = (v: Record<string, number> | string): Record<string, number> => {
    if (v == null) return {};
    if (typeof v === 'string') {
      try {
        const parsed = JSON.parse(v);
        return typeof parsed === 'object' && parsed !== null ? parsed : {};
      } catch {
        return {};
      }
    }
    return v;
  };
  const A = parse(a);
  const B = parse(b);
  const merged: Record<string, number> = {};
  for (const [k, v] of Object.entries(A)) merged[k] = v;
  for (const [k, v] of Object.entries(B)) {
    merged[k] = Math.max(merged[k] ?? 0, v ?? 0);
  }
  return merged;
}

/** Which device's version wins (higher vector-clock sum wins). */
export function compareVectorClocks(
  a: Record<string, number> | string,
  b: Record<string, number> | string,
): 'a' | 'b' | 'equal' {
  const A = mergeVectorClocks(a, {});
  const B = mergeVectorClocks(b, {});
  const sumA = Object.values(A).reduce((s, v) => s + (v || 0), 0);
  const sumB = Object.values(B).reduce((s, v) => s + (v || 0), 0);
  if (sumA === sumB) return 'equal';
  return sumA > sumB ? 'a' : 'b';
}

export interface ConflictInput {
  incoming: Record<string, unknown>;
  existing: Record<string, unknown> | null;
  incomingDeviceId: string;
}

export interface ConflictResult {
  action: 'apply' | 'conflict' | 'skip';
  merged?: Record<string, unknown>;
  reason?: string;
}

/**
 * Resolve a single push change against the existing server row.
 * - Optimistic lock via `version`.
 * - Tombstone precedence: a soft delete always wins over a live row.
 * - vectorClock merge on conflict.
 */
export function resolveConflict(input: ConflictInput): ConflictResult {
  const { incoming, existing, incomingDeviceId } = input;

  // Tombstone precedence: incoming delete always wins.
  if (incoming.deletedAt && incoming.deletedAt !== 0 && incoming.deletedAt !== null) {
    return {
      action: 'apply',
      merged: {
        ...(existing ?? {}),
        ...incoming,
        deletedAt: incoming.deletedAt,
        vectorClock: JSON.stringify(
          mergeVectorClocks(
            (existing as any)?.vectorClock ?? '{}',
            (incoming as any).vectorClock ?? `{ "${incomingDeviceId}": 1 }`,
          ),
        },
        version: ((existing as any)?.version ?? 0) + 1,
      },
    };
  }

  if (!existing) {
    return { action: 'apply', merged: incoming };
  }

  const existingVersion = (existing as any).version ?? 0;
  const incomingVersion = (incoming as any).version ?? 0;

  // Optimistic lock: server row is newer than the incoming change.
  if (existingVersion > incomingVersion) {
    const cmp = compareVectorClocks(
      (existing as any).vectorClock ?? '{}',
      (incoming as any).vectorClock ?? '{}',
    );
    if (cmp === 'b') {
      // Incoming has a strictly newer clock — apply anyway.
      return {
        action: 'apply',
        merged: {
          ...existing,
          ...incoming,
          version: existingVersion + 1,
          vectorClock: JSON.stringify(
            mergeVectorClocks(
              (existing as any).vectorClock ?? '{}',
              (incoming as any).vectorClock ?? '{}',
            ),
          ),
        },
      };
    }
    return {
      action: 'conflict',
      reason: `version mismatch: server=${existingVersion} incoming=${incomingVersion}`,
    };
  }

  return {
    action: 'apply',
    merged: {
      ...existing,
      ...incoming,
      version: Math.max(existingVersion, incomingVersion) + 1,
      vectorClock: JSON.stringify(
        mergeVectorClocks(
          (existing as any).vectorClock ?? '{}',
          (incoming as any).vectorClock ?? '{}',
        ),
      ),
    },
  };
}