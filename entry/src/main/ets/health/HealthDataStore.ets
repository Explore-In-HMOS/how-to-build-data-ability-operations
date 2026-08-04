/*
 * Local, on-device data sink for the sync bridge, backed by relationalStore (RDB).
 *
 * This is the Stage-model, testable successor to the FA-model "DataAbilityHelper
 * .executeBatch" flow from the original spec: instead of a client-side batch of
 * DataAbilityOperation (FA only, not available in this Stage project), we run a
 * genuine multi-row batch inside an explicit RDB transaction so the batch is
 * atomic — all rows commit or all roll back. Every row is tagged with a per-run
 * sync_batch_id so a failure can be cleaned up deterministically.
 */
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { HealthMetric, SyncError, SyncErrorCode } from '../common/SyncTypes';
import { Logger } from '../common/Logger';

const DB_NAME: string = 'health_sync.db';
const TABLE: string = 'health_metrics';
const CREATE_SQL: string = `CREATE TABLE IF NOT EXISTS ${TABLE} (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  record_id TEXT NOT NULL,
  timestamp INTEGER NOT NULL,
  step_count INTEGER NOT NULL,
  heart_rate INTEGER NOT NULL,
  source_device TEXT,
  sync_batch_id TEXT NOT NULL)`;

export class HealthDataStore {
  private store: relationalStore.RdbStore | undefined = undefined;

  /** Idempotent: opens the RDB and ensures the table exists. */
  async init(context: common.Context): Promise<void> {
    if (this.store !== undefined) {
      return;
    }
    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    this.store = await relationalStore.getRdbStore(context, config);
    await this.store.executeSql(CREATE_SQL);
    Logger.i('RDB ready: %{public}s', DB_NAME);
  }

  /**
   * Atomic batch insert. All metrics commit together, or the whole batch rolls
   * back. Returns the number of rows inserted. Throws RESULT_COUNT_MISMATCH when
   * the store confirms fewer rows than requested (then rolls back).
   */
  async batchInsertAtomic(metrics: HealthMetric[], batchId: string): Promise<number> {
    const store: relationalStore.RdbStore = this.requireStore();

    const buckets: relationalStore.ValuesBucket[] = metrics.map((m: HealthMetric): relationalStore.ValuesBucket => {
      const vb: relationalStore.ValuesBucket = {
        'record_id': m.recordId,
        'timestamp': m.timestamp,
        'step_count': m.stepCount,
        'heart_rate': m.heartRate,
        'source_device': m.sourceDevice,
        'sync_batch_id': batchId
      };
      return vb;
    });

    store.beginTransaction();
    try {
      const inserted: number = await store.batchInsert(TABLE, buckets);
      if (inserted < 0 || inserted !== metrics.length) {
        store.rollBack();
        throw new SyncError(
          SyncErrorCode.RESULT_COUNT_MISMATCH,
          `batchInsert affected ${inserted} rows, expected ${metrics.length} — rolled back`
        );
      }
      store.commit();
      Logger.i('Committed %{public}d rows (batch %{public}s)', inserted, batchId);
      return inserted;
    } catch (e) {
      // Ensure the transaction is not left open on any failure path.
      try {
        store.rollBack();
      } catch (rollbackErr) {
        // Transaction was already rolled back / not active — safe to ignore.
        Logger.d('rollBack on failed batch ignored: %{public}s', (rollbackErr as Error).message);
      }
      if (e instanceof SyncError) {
        throw e;
      }
      const be = e as BusinessError;
      throw new SyncError(SyncErrorCode.BATCH_EXECUTION_FAILED, 'batchInsert failed: ' + (be.message ?? 'unknown'));
    }
  }

  /** Compensating cleanup: delete every row tagged with the given batch id. */
  async rollbackBatch(batchId: string): Promise<number> {
    const store: relationalStore.RdbStore = this.requireStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('sync_batch_id', batchId);
    const removed: number = await store.delete(predicates);
    Logger.i('Rolled back %{public}d rows (batch %{public}s)', removed, batchId);
    return removed;
  }

  /** Total rows currently persisted — used by the UI to show real progress. */
  async totalRows(): Promise<number> {
    const store: relationalStore.RdbStore = this.requireStore();
    const rs: relationalStore.ResultSet = await store.querySql(`SELECT COUNT(*) AS cnt FROM ${TABLE}`);
    try {
      if (rs.goToFirstRow()) {
        return rs.getLong(rs.getColumnIndex('cnt'));
      }
      return 0;
    } finally {
      rs.close();
    }
  }

  async clearAll(): Promise<void> {
    const store: relationalStore.RdbStore = this.requireStore();
    await store.executeSql(`DELETE FROM ${TABLE}`);
    Logger.i('Cleared table %{public}s', TABLE);
  }

  private requireStore(): relationalStore.RdbStore {
    if (this.store === undefined) {
      throw new SyncError(SyncErrorCode.HELPER_UNAVAILABLE, 'RDB store not initialized — call init() first');
    }
    return this.store;
  }
}
