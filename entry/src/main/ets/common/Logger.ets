import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0xD001;
const TAG: string = 'HealthSyncBridge';

/** Thin hilog wrapper so call sites stay terse and the domain/tag are consistent. */
export class Logger {
  static i(fmt: string, ...args: (string | number)[]): void {
    hilog.info(DOMAIN, TAG, fmt, ...args);
  }
  static w(fmt: string, ...args: (string | number)[]): void {
    hilog.warn(DOMAIN, TAG, fmt, ...args);
  }
  static e(fmt: string, ...args: (string | number)[]): void {
    hilog.error(DOMAIN, TAG, fmt, ...args);
  }
  static d(fmt: string, ...args: (string | number)[]): void {
    hilog.debug(DOMAIN, TAG, fmt, ...args);
  }
}
