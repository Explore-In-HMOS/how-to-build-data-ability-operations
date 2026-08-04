/*
 * Context-aware sync-interval recommendation.
 *
 * IMPORTANT: the `Recommended` utility class named in the original spec does NOT
 * exist in the HarmonyOS SDK. The production-grade signal is the App Standby group
 * via @ohos.resourceschedule.usageStatistics.queryAppGroup() — that real version is
 * kept in reference/stage-usagestats/SyncIntervalAdvisor_usageStats.ets.
 *
 * Under this project's strict ArkTS toolchain the `usageStatistics` namespace is not
 * usable as a value, so the COMPILED advisor derives a safe cadence from an
 * always-available, dependency-free context signal: the local time-of-day activity
 * window. Swap in the usageStatistics version once your SDK image resolves it.
 */

export enum RecommendedIntervalMs {
  REALTIME = 60000,      // 1 min
  FREQUENT = 300000,     // 5 min
  NORMAL = 900000,       // 15 min
  RARE = 3600000,        // 1 h
  DEFERRED = 10800000    // 3 h
}

export class SyncIntervalAdvisor {
  /** Map the current activity window to a sync cadence. */
  static recommendIntervalMs(): number {
    const hour: number = new Date().getHours();
    if (hour >= 6 && hour < 9) {
      return RecommendedIntervalMs.FREQUENT;   // morning activity peak
    }
    if (hour >= 9 && hour < 22) {
      return RecommendedIntervalMs.NORMAL;     // daytime
    }
    if (hour >= 22 || hour < 1) {
      return RecommendedIntervalMs.RARE;       // wind-down
    }
    return RecommendedIntervalMs.DEFERRED;     // deep night (01:00–06:00)
  }
}
