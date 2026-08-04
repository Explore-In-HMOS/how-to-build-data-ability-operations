/*
 * Shared, model-neutral types for the Watch Companion Health Sync Bridge.
 * Consumed by the health/* logic modules and the pages/* ArkUI layer.
 */

/** UI-facing lifecycle states rendered by the responsive status matrix. */
export enum SyncState {
  IDLE = 'IDLE',
  CONNECTING = 'CONNECTING',
  CONNECTED = 'CONNECTED',
  IN_PROGRESS = 'IN_PROGRESS',
  SUCCESS = 'SUCCESS',
  FAILED = 'FAILED',
  MISMATCH = 'MISMATCH'
}

/** One health sample pushed from the wearable. `recordId` is the idempotency key. */
export interface HealthMetric {
  recordId: string;
  timestamp: number; // epoch millis
  stepCount: number;
  heartRate: number;
  sourceDevice: string;
}

export enum SyncErrorCode {
  NONE = 0,
  REMOTE_LAUNCH_FAILED = 1001,
  CONNECTION_TIMEOUT = 1002,
  HELPER_UNAVAILABLE = 1003,
  BATCH_EXECUTION_FAILED = 1004,
  RESULT_COUNT_MISMATCH = 1005,
  ROLLBACK_FAILED = 1006,
  PERMISSION_DENIED = 1007,
  TARGET_NOT_READY = 1008
}

export class SyncError extends Error {
  code: SyncErrorCode;

  constructor(code: SyncErrorCode, message: string) {
    super(message);
    this.name = 'SyncError';
    this.code = code;
  }
}

/** Transient/connectivity faults are retried; data faults (mismatch) are not. */
export const RETRYABLE_CODES: Set<SyncErrorCode> = new Set<SyncErrorCode>([
  SyncErrorCode.REMOTE_LAUNCH_FAILED,
  SyncErrorCode.CONNECTION_TIMEOUT,
  SyncErrorCode.TARGET_NOT_READY,
  SyncErrorCode.HELPER_UNAVAILABLE
]);

export interface SyncOutcome {
  state: SyncState;
  affectedRows: number;
  errorCode: SyncErrorCode;
  message: string;
  durationMs: number;
  batchId: string;
}

export type SyncStateListener = (state: SyncState, outcome?: SyncOutcome) => void;
