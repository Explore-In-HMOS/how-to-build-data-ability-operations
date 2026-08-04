/*
 * Responsive Wearable Status Matrix — a NavDestination tuned for a ROUND screen.
 *
 * Uses ScreenMetrics (@ohos.display) to size a centered content band that never clips
 * on the circular glass, wrapped in a Scroll so taller states stay reachable. Renders
 * every lifecycle state (Progress, Connected, Success, Failed, Mismatch).
 *
 * - "Sync now" runs the local atomic RDB batch (fully testable on the emulator).
 * - "Cross-device" runs the same batch behind the real CompletionHandlerForAtomicService
 *   readiness gate. On a standalone emulator with no paired provider it reports a
 *   graceful FAILED/Mismatch — which itself proves the atomic-service callback fired.
 */
import { common } from '@kit.AbilityKit';
import { HealthDataStore } from '../health/HealthDataStore';
import { HealthSyncBridge, SyncOptions } from '../health/HealthSyncBridge';
import { SyncIntervalAdvisor } from '../health/SyncIntervalAdvisor';
import { RemoteReadinessGate } from '../health/RemoteReadinessGate';
import { ScreenMetrics } from '../common/ScreenMetrics';
import { HealthMetric, SyncState, SyncOutcome } from '../common/SyncTypes';

interface StateStyle {
  label: string;
  color: string;
  glyph: string;
}

const DEMO_ATOMIC_APP_ID: string = 'com.hmosdemos.wearable.phoneprovider';

@Component
export struct SyncStatusMatrix {
  @State private current: SyncState = SyncState.IDLE;
  @State private message: string = 'Ready to sync';
  @State private affectedRows: number = 0;
  @State private totalRows: number = 0;
  @State private intervalMin: number = 15;
  @State private busy: boolean = false;
  @State private contentWidth: number = 172;
  @State private vInset: number = 24;

  private store: HealthDataStore = new HealthDataStore();
  private readonly matrixOrder: SyncState[] = [
    SyncState.IN_PROGRESS, SyncState.CONNECTED, SyncState.SUCCESS,
    SyncState.FAILED, SyncState.MISMATCH
  ];

  aboutToAppear(): void {
    this.contentWidth = ScreenMetrics.safeContentWidthVp();
    this.vInset = ScreenMetrics.verticalInsetVp();
    this.intervalMin = Math.round(SyncIntervalAdvisor.recommendIntervalMs() / 60000);
    this.initialize();
  }

  private async initialize(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await this.store.init(ctx);
      this.totalRows = await this.store.totalRows();
    } catch (e) {
      this.message = 'Store init failed: ' + (e as Error).message;
      this.current = SyncState.FAILED;
    }
  }

  private styleFor(s: SyncState): StateStyle {
    switch (s) {
      case SyncState.CONNECTING:
        return { label: 'Connecting', color: '#3E7BFA', glyph: '⟳' };
      case SyncState.CONNECTED:
        return { label: 'Connected', color: '#00A0FF', glyph: '⇄' };
      case SyncState.IN_PROGRESS:
        return { label: 'Progress', color: '#F5A623', glyph: '◔' };
      case SyncState.SUCCESS:
        return { label: 'Success', color: '#28C840', glyph: '✓' };
      case SyncState.FAILED:
        return { label: 'Failed', color: '#FF4D4F', glyph: '✕' };
      case SyncState.MISMATCH:
        return { label: 'Mismatch', color: '#C0392B', glyph: '≠' };
      default:
        return { label: 'Idle', color: '#8C8C8C', glyph: '•' };
    }
  }

  private buildSampleMetrics(): HealthMetric[] {
    const now: number = Date.now();
    const metrics: HealthMetric[] = [
      { recordId: `${now}-a`, timestamp: now, stepCount: 5231, heartRate: 78, sourceDevice: 'watch' },
      { recordId: `${now}-b`, timestamp: now + 1, stepCount: 5240, heartRate: 81, sourceDevice: 'watch' },
      { recordId: `${now}-c`, timestamp: now + 2, stepCount: 5258, heartRate: 79, sourceDevice: 'watch' }
    ];
    return metrics;
  }

  private makeBridge(): HealthSyncBridge {
    return new HealthSyncBridge(this.store, (state: SyncState, outcome?: SyncOutcome) => {
      this.current = state;
      if (outcome !== undefined) {
        this.message = outcome.message;
        this.affectedRows = outcome.affectedRows;
      }
    });
  }

  private async runLocalSync(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    const outcome: SyncOutcome = await this.makeBridge().sync(this.buildSampleMetrics());
    this.current = outcome.state;
    this.message = outcome.message;
    this.affectedRows = outcome.affectedRows;
    this.totalRows = await this.store.totalRows();
    this.busy = false;
  }

  private async runCrossDeviceSync(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const options: SyncOptions = {
      gate: () => RemoteReadinessGate.gateOnAtomicService(ctx, DEMO_ATOMIC_APP_ID),
      gateTimeoutMs: 6000,
      maxAttempts: 1
    };
    const outcome: SyncOutcome = await this.makeBridge().sync(this.buildSampleMetrics(), options);
    this.current = outcome.state;
    this.message = outcome.message;
    this.affectedRows = outcome.affectedRows;
    this.totalRows = await this.store.totalRows();
    this.busy = false;
  }

  private async clearStore(): Promise<void> {
    if (this.busy) {
      return;
    }
    try {
      await this.store.clearAll();
      this.totalRows = 0;
      this.affectedRows = 0;
      this.current = SyncState.IDLE;
      this.message = 'Store cleared';
    } catch (e) {
      this.message = 'Clear failed: ' + (e as Error).message;
    }
  }

  @Builder
  StatusChip(s: SyncState) {
    Column() {
      Text(this.styleFor(s).glyph)
        .fontSize(18)
        .fontColor(this.current === s ? Color.White : this.styleFor(s).color)
      Text(this.styleFor(s).label)
        .fontSize(9)
        .maxLines(1)
        .fontColor(this.current === s ? Color.White : '#B0B0B0')
        .margin({ top: 1 })
    }
    .width('30%')
    .aspectRatio(1)
    .justifyContent(FlexAlign.Center)
    .borderRadius(10)
    .backgroundColor(this.current === s ? this.styleFor(s).color : '#1C1C1E')
    .margin(2)
  }

  build() {
    NavDestination() {
      Stack() {
        Scroll() {
          Column({ space: 6 }) {
            // Primary status ring
            Stack() {
              Circle()
                .width(84)
                .height(84)
                .fill(Color.Transparent)
                .stroke(this.styleFor(this.current).color)
                .strokeWidth(6)
              Text(this.styleFor(this.current).glyph)
                .fontSize(28)
                .fontColor(this.styleFor(this.current).color)
            }
            .width(84)
            .height(84)

            Text(this.styleFor(this.current).label)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)

            Text(this.message)
              .fontSize(10)
              .fontColor('#9A9A9A')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Center)

            // Responsive state matrix — wraps to fit the round face
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
              ForEach(this.matrixOrder, (s: SyncState) => {
                this.StatusChip(s);
              }, (s: SyncState) => s.toString())
            }
            .width('100%')
            .margin({ top: 2 })

            Text(`Rows ${this.totalRows} · +${this.affectedRows} · ${this.intervalMin}m`)
              .fontSize(9)
              .fontColor('#6E6E6E')

            Button(this.busy ? 'Syncing…' : 'Sync now')
              .enabled(!this.busy)
              .width('100%')
              .height(38)
              .fontSize(14)
              .margin({ top: 2 })
              .onClick(() => {
                this.runLocalSync();
              })

            Button('Cross-device')
              .enabled(!this.busy)
              .width('100%')
              .height(32)
              .fontSize(12)
              .backgroundColor('#2C2C2E')
              .onClick(() => {
                this.runCrossDeviceSync();
              })

            Button('Clear')
              .enabled(!this.busy)
              .width('100%')
              .height(32)
              .fontSize(12)
              .backgroundColor('#2C2C2E')
              .onClick(() => {
                this.clearStore();
              })
          }
          .width('100%')
          .constraintSize({ minHeight: '100%' })
          .justifyContent(FlexAlign.Center)
          .padding({ top: this.vInset, bottom: this.vInset })
        }
        .width(this.contentWidth)
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Center)
      .backgroundColor(Color.Black)
    }
    .hideTitleBar(true)
  }
}
