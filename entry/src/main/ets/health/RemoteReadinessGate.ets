/*
 * Remote Ability Launch Lifecycle gate (Stage model, API 20+).
 *
 * This is the CORRECT, real implementation of requirement #2. The original spec
 * named `CompletionHandlerForAbilityStartCallback`, which does not exist — the
 * real symbols are `CompletionHandler` and `CompletionHandlerForAtomicService`, so
 * that batch sync begins only AFTER the target confirms it is fully started.
 *
 * IMPORTANT: these are declared as `export default class` with declaration-only
 * methods — nominal to the type checker, but with NO runtime constructor. So you can
 * neither `implements` them (arkts-implements-only-iface) nor `extends` them (runtime
 * "parent class is not constructor"). The official pattern is an OBJECT LITERAL typed
 * as the type (the annotation is erased at runtime; the framework duck-types the
 * object's methods). See the CompletionHandler reference "Example".
 */
import { common, Want, StartOptions, AtomicServiceOptions,
         CompletionHandler, CompletionHandlerForAtomicService, FailureCode,
         bundleManager } from '@kit.AbilityKit';
import { SyncError, SyncErrorCode } from '../common/SyncTypes';
import { Logger } from '../common/Logger';

export class RemoteReadinessGate {
  /** Gate on a full UIAbility start using the real CompletionHandler. */
  static gateOnAbility(context: common.UIAbilityContext, want: Want): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      const completionHandler: CompletionHandler = {
        onRequestSuccess: (elementName: bundleManager.ElementName, message: string): void => {
          Logger.i('Ability ready: %{public}s/%{public}s (%{public}s)',
            elementName.bundleName, elementName.abilityName, message);
          resolve();
        },
        onRequestFailure: (elementName: bundleManager.ElementName, message: string): void => {
          reject(new SyncError(SyncErrorCode.TARGET_NOT_READY,
            `Target ${elementName.abilityName} not ready: ${message}`));
        }
      };
      const options: StartOptions = { completionHandler: completionHandler };
      context.startAbility(want, options).catch((e: Object) => {
        reject(new SyncError(SyncErrorCode.REMOTE_LAUNCH_FAILED,
          'startAbility rejected: ' + (e as Error).message));
      });
    });
  }

  /** Gate on a lightweight atomic service using CompletionHandlerForAtomicService. */
  static gateOnAtomicService(context: common.UIAbilityContext, appId: string): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      const completionHandler: CompletionHandlerForAtomicService = {
        onAtomicServiceRequestSuccess: (id: string): void => {
          Logger.i('Atomic service ready: %{public}s', id);
          resolve();
        },
        onAtomicServiceRequestFailure: (id: string, failureCode: FailureCode, failureMessage: string): void => {
          // failureCode: 0 SYSTEM_MALFUNCTION, 1 USER_CANCEL, 2 USER_REFUSE
          reject(new SyncError(SyncErrorCode.TARGET_NOT_READY,
            `Atomic service ${id} failed (code ${failureCode}): ${failureMessage}`));
        }
      };
      const options: AtomicServiceOptions = { completionHandlerForAtomicService: completionHandler };
      context.openAtomicService(appId, options).then(() => {
        // openAtomicService resolves with the AbilityResult; readiness is signaled
        // through the handler above, so nothing more is needed here.
      }).catch((e: Object) => {
        reject(new SyncError(SyncErrorCode.TARGET_NOT_READY,
          'openAtomicService rejected: ' + (e as Error).message));
      });
    });
  }
}
