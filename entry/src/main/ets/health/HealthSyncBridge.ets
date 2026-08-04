/*
 * Distributed Batch Sync Engine — orchestrator.
 *
 * Flow: (optional) remote readiness gate -> atomic batch write -> validate ->
 * rollback on mismatch -> SyncOutcome. Handles connection timeouts and retries
 * transient faults with exponential backoff + jitter (to absorb cross-device
 * latency spikes), but never retries a data mismatch (that would duplicate rows).
 *
 * The readiness gate is injected (dependency inversion) so this engine does not
 * hard-depend on the API-20 RemoteReadinessGate; the local RDB path works with no
 * gate at all, which is what the default UI flow exercises.
 */
import { util } from '@kit.ArkTS';
import {
  HealthMetric, SyncError, SyncErrorCode, SyncOutcome, SyncState,
  SyncStateListener, RETRYABLE_CODES
} from '../common/SyncTypes';
import { HealthDataStore } from './HealthDataStore';
import { Logger } from '../common/Logger';

/** A pluggable "target is ready" check; resolves when sync may proceed. */
export type ReadinessGate = () => Promise<void>;

export interface SyncOptions {
  gate?: ReadinessGate;
  maxAttempts?: number;
  gateTimeoutMs?: number;
}

export class HealthSyncBridge {
  private store: HealthDataStore;
  private listener: SyncStateListener | undefined;

  constructor(store: HealthDataStore, listener?: SyncStateListener) {
    this.store = store;
    this.listener = listener;
  }

  async sync(metrics: HealthMetric[], options?: SyncOptions): Promise<SyncOutcome> {
    const started: number = Date.now();
    const batchId: string = util.generateRandomUUID(true);
    const maxAttempts: number = options?.maxAttempts ?? 3;
    const gate: ReadinessGate | undefined = options?.gate;
    const gateTimeoutMs: number = options?.gateTimeoutMs ?? 8000;

    if (metrics.length === 0) {
      const empty: SyncOutcome = {
        state: SyncState.SUCCESS, affectedRows: 0, errorCode: SyncErrorCode.NONE,
        message: 'Nothing to sync', durationMs: 0, batchId: batchId
      };
      this.emit(SyncState.SUCCESS, empty);
      return empty;
    }

    let lastError: SyncError = new SyncError(SyncErrorCode.BATCH_EXECUTION_FAILED, 'Sync not attempted');
    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        if (gate !== undefined) {
          this.emit(SyncState.CONNECTING);
          await this.withTimeout(gate(), gateTimeoutMs, SyncErrorCode.CONNECTION_TIMEOUT, 'Readiness gate timed out');
          this.emit(SyncState.CONNECTED);
        }

        this.emit(SyncState.IN_PROGRESS);
        const inserted: number = await this.store.batchInsertAtomic(metrics, batchId);
        const total: number = await this.store.totalRows();

        const ok: SyncOutcome = {
          state: SyncState.SUCCESS, affectedRows: inserted, errorCode: SyncErrorCode.NONE,
          message: `Synced ${inserted} metrics · store total ${total}`,
          durationMs: Date.now() - started, batchId: batchId
        };
        this.emit(SyncState.SUCCESS, ok);
        return ok;
      } catch (e) {
        lastError = this.asSyncError(e);
        Logger.w('sync attempt %{public}d/%{public}d failed code=%{public}d msg=%{public}s',
          attempt, maxAttempts, lastError.code, lastError.message);

        if (lastError.code === SyncErrorCode.RESULT_COUNT_MISMATCH) {
          // Transaction already rolled back inside the store; this is a belt-and-braces
          // compensating cleanup in case any partial rows survived a provider quirk.
          try {
            await this.store.rollbackBatch(batchId);
          } catch (re) {
            Logger.e('compensating rollback failed: %{public}s', (re as Error).message);
          }
        }

        if (!RETRYABLE_CODES.has(lastError.code) || attempt === maxAttempts) {
          break;
        }
        await this.delay(this.backoffMs(attempt));
      }
    }

    const state: SyncState =
      lastError.code === SyncErrorCode.RESULT_COUNT_MISMATCH ? SyncState.MISMATCH : SyncState.FAILED;
    const fail: SyncOutcome = {
      state: state, affectedRows: 0, errorCode: lastError.code, message: lastError.message,
      durationMs: Date.now() - started, batchId: batchId
    };
    this.emit(state, fail);
    return fail;
  }

  private emit(state: SyncState, outcome?: SyncOutcome): void {
    if (this.listener !== undefined) {
      this.listener(state, outcome);
    }
  }

  private withTimeout<T>(p: Promise<T>, ms: number, code: SyncErrorCode, msg: string): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      const timer = setTimeout(() => {
        reject(new SyncError(code, msg));
      }, ms);
      p.then((v: T) => {
        clearTimeout(timer);
        resolve(v);
      }).catch((e: Object) => {
        clearTimeout(timer);
        reject(this.asSyncError(e));
      });
    });
  }

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  /** Exponential backoff capped at 4s, plus jitter, to smooth cross-device retries. */
  private backoffMs(attempt: number): number {
    const base: number = Math.min(4000, 500 * Math.pow(2, attempt - 1));
    const jitter: number = Date.now() % 250;
    return base + jitter;
  }

  private asSyncError(e: Object): SyncError {
    if (e instanceof SyncError) {
      return e;
    }
    const err = e as Error;
    return new SyncError(SyncErrorCode.BATCH_EXECUTION_FAILED, err.message ?? 'Unexpected error');
  }
}
