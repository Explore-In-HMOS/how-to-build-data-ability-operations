/*
 * Circular-screen geometry helper for round wearables.
 *
 * Uses @ohos.display (via @kit.ArkUI) to read the real screen size, then derives a
 * centered content band that never clips on a round face. On a circle the fully
 * usable width is only at the vertical midline; corners are unusable. Constraining
 * content to ~0.74 of the diameter (just above the inscribed square, 0.707) and
 * centering it keeps every element inside the glass.
 */
import { display } from '@kit.ArkUI';
import { Logger } from './Logger';

export class ScreenMetrics {
  private static diameterVpCache: number = 0;

  /** Shorter screen edge in vp — the circle diameter on a round watch. */
  static diameterVp(): number {
    if (ScreenMetrics.diameterVpCache > 0) {
      return ScreenMetrics.diameterVpCache;
    }
    let diameter: number = 233; // fallback ≈ 466px @ 2.0 density
    try {
      const d: display.Display = display.getDefaultDisplaySync();
      const shorterPx: number = Math.min(d.width, d.height);
      const density: number = d.densityPixels > 0 ? d.densityPixels : 1;
      diameter = shorterPx / density;
    } catch (e) {
      Logger.w('display query failed (%{public}s); using fallback diameter', (e as Error).message);
    }
    ScreenMetrics.diameterVpCache = diameter;
    return diameter;
  }

  /** Width (vp) of a centered content band that stays inside the round glass. */
  static safeContentWidthVp(factor: number = 0.74): number {
    return Math.floor(ScreenMetrics.diameterVp() * factor);
  }

  /** Vertical inset (vp) so the top/bottom items clear the narrowing of the circle. */
  static verticalInsetVp(): number {
    return Math.round(ScreenMetrics.diameterVp() * 0.10);
  }
}
