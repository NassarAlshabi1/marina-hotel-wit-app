/**
 * Sync logger — writes structured sync events to D1 `sync_log`.
 */

import type { Env, SyncLogEntry } from '../types';
import { writeSyncLog } from './database';

export class SyncLogger {
  constructor(private env: Env) {}

  async log(entry: SyncLogEntry): Promise<void> {
    try {
      await writeSyncLog(this.env.DB, entry);
    } catch {
      // Never block sync on logging.
    }
  }

  logAsync(entry: SyncLogEntry): void {
    this.log(entry).catch(() => undefined);
  }
}