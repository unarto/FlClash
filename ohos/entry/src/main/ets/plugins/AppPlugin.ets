import common from '@ohos.app.ability.common';
import Want from '@ohos.app.ability.Want';
import vpnExtension from '@ohos.net.vpnExtension';
import photoAccessHelper from '@ohos.file.photoAccessHelper';
import fileUri from '@ohos.file.fileuri';
import { fileIo as fs, fileShare } from '@kit.CoreFileKit';
import { UIAbility } from '@kit.AbilityKit';
import pasteboard from '@ohos.pasteboard';
import {
  AbilityPluginBinding,
  Any,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import { stringifyError } from './error_utils';
import { resolveVpnStartResult } from './vpn_start_decision';
import { resolveVpnStopResult } from './vpn_stop_decision';

interface NativeBridge {
  invokeCore(action: string): string;
  invokeCoreAsync(action: string): Promise<string>;
  consumeCoreEvents(): string;
  chmodPath(path: string): boolean;
  probeCreateNativeChildProcess(): number;
  startCoreChildProcess(entryParams: string): number;
  startBundledCoreProcess(
    sourcePath: string,
    socketPath: string,
    logDirPath: string,
  ): number;
  startEmbeddedCore(socketPath: string, logDirPath: string): number;
  stopTrackedCore(): boolean;
  startTun(fd: number, stack: string, address: string, dns: string): boolean;
  stopTun(): boolean;
  lastError(): string;
}

interface PendingDebugVpnStart {
  stack: string;
  ipv6: boolean;
}

const nativeBridge = loadNativeModule('libentry.so') as NativeBridge;
const VPN_STATUS_FILE_NAME = 'flclash-vpn-status.txt';

function readAllBytes(path: string): Uint8Array {
  const stat = fs.statSync(path);
  const expectedSize = Number(stat.size);
  if (expectedSize <= 0) {
    return new Uint8Array();
  }
  const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
  try {
    const output = new Uint8Array(expectedSize);
    let totalRead = 0;
    while (totalRead < expectedSize) {
      const chunkSize = Math.min(expectedSize - totalRead, 64 * 1024);
      const chunkBuffer = new ArrayBuffer(chunkSize);
      const readSize = fs.readSync(file.fd, chunkBuffer);
      if (readSize <= 0) {
        break;
      }
      output.set(new Uint8Array(chunkBuffer, 0, readSize), totalRead);
      totalRead += readSize;
    }
    return totalRead === expectedSize ? output : output.slice(0, totalRead);
  } finally {
    fs.closeSync(file);
  }
}

function writeAllBytes(uri: string, bytes: Uint8Array): void {
  try {
    fs.unlinkSync(uri);
  } catch (_) {}
  const target = fs.openSync(uri, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
  try {
    const buffer = bytes.byteOffset === 0 && bytes.byteLength === bytes.buffer.byteLength
      ? bytes.buffer
      : bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
    let pending = buffer;
    while (pending.byteLength > 0) {
      const written = fs.writeSync(target.fd, pending);
      if (written <= 0) {
        throw new Error(`Failed to write shared download file: written=${written}`);
      }
      pending = pending.slice(written);
    }
  } finally {
    fs.closeSync(target);
  }
}

async function prepareWritePermission(uri: string): Promise<void> {
  const policy: fileShare.PolicyInfo = {
    uri,
    operationMode: fileShare.OperationMode.WRITE_MODE,
  };
  const persisted = await fileShare.checkPersistentPermission([policy]);
  if (persisted.length === 0 || !persisted[0]) {
    await fileShare.persistPermission([policy]);
  }
  await fileShare.activatePermission([policy]);
}

export default class AppPlugin implements FlutterPlugin, MethodCallHandler {
  private static pendingLinks: string[] = [];
  private static appLinkListenerReady = false;
  private static pendingLinkDeliveryInFlight = false;
  private static pendingLinkInFlightValue: string = '';
  private static pendingLinkDeliveryId = 0;
  private static pendingDebugVpnStarts: PendingDebugVpnStart[] = [];
  private static pendingDebugVpnStartListenerReady = false;
  private static pendingDebugVpnStartDeliveryInFlight = false;
  private static pendingDebugVpnStartInFlightValue: PendingDebugVpnStart | null = null;
  private static pendingDebugVpnStartDeliveryId = 0;
  private static activeChannel: MethodChannel | null = null;
  private static lastImportedGalleryUri: string = '';
  private static lastImportedGalleryIdentifier: string = '';
  private static lastFilePickerState: string = '';
  private static lastClipboardText: string = '';
  private pluginBinding: FlutterPluginBinding | null = null;
  private abilityBinding: AbilityPluginBinding | null = null;
  private channel: MethodChannel | null = null;
  private ability: UIAbility | null = null;
  private applicationContext: common.Context | null = null;
  private isVpnRunning = false;
  private vpnStartInFlight = false;

  private getVpnStatusPath(context: common.Context): string {
    return `${context.filesDir}/${VPN_STATUS_FILE_NAME}`;
  }

  private resetVpnStatus(path: string): void {
    try {
      fs.unlinkSync(path);
    } catch (_) {}
  }

  private readVpnStatus(path: string): string {
    try {
      return fs.readTextSync(path).trim();
    } catch (_) {
      return '';
    }
  }

  private isVpnStatusRunning(context: common.Context | null): boolean {
    if (context == null) {
      return this.isVpnRunning;
    }
    const status = this.readVpnStatus(this.getVpnStatusPath(context));
    return status === 'started' || (status.length === 0 && this.isVpnRunning);
  }

  private async waitForVpnStatus(path: string): Promise<string> {
    for (let index = 0; index < 30; index += 1) {
      const status = this.readVpnStatus(path);
      if (
        status === 'started' ||
        status.startsWith('failed:')
      ) {
        return status;
      }
      await new Promise<void>((resolve) => setTimeout(resolve, 100));
    }
    return this.readVpnStatus(path);
  }

  private async waitForVpnStoppedStatus(path: string): Promise<string> {
    for (let index = 0; index < 30; index += 1) {
      const status = this.readVpnStatus(path);
      if (
        status === 'stopped' ||
        status.startsWith('failed:')
      ) {
        return status;
      }
      await new Promise<void>((resolve) => setTimeout(resolve, 100));
    }
    return this.readVpnStatus(path);
  }

  private shouldRetryFailedVpnStopStatus(status: string): boolean {
    return (
      status.includes('stopTun failed:') ||
      status.includes('stopTrackedCore failed:') ||
      status.includes('destroy failed:')
    );
  }

  private async withTimeout<T>(
    promise: Promise<T>,
    timeoutMs: number,
    timeoutMessage: string,
  ): Promise<T> {
    return await Promise.race([
      promise,
      new Promise<T>((_, reject) => {
        setTimeout(() => reject(new Error(timeoutMessage)), timeoutMs);
      }),
    ]) as T;
  }

  private static deliverPendingLinkIfReady(): void {
    if (
      AppPlugin.pendingLinks.length === 0 ||
      !AppPlugin.appLinkListenerReady ||
      AppPlugin.activeChannel == null ||
      AppPlugin.pendingLinkDeliveryInFlight
    ) {
      return;
    }
    const link = AppPlugin.pendingLinks[0];
    if (link == null) {
      return;
    }
    const deliveryId = AppPlugin.pendingLinkDeliveryId + 1;
    AppPlugin.pendingLinkDeliveryId = deliveryId;
    AppPlugin.pendingLinkDeliveryInFlight = true;
    AppPlugin.pendingLinkInFlightValue = link;
    AppPlugin.activeChannel.invokeMethod('appLink', link, {
      success: () => {
        if (AppPlugin.pendingLinkDeliveryId !== deliveryId) {
          return;
        }
        AppPlugin.pendingLinkDeliveryInFlight = false;
        AppPlugin.pendingLinkInFlightValue = '';
        if (AppPlugin.pendingLinks.length > 0 && AppPlugin.pendingLinks[0] === link) {
          AppPlugin.pendingLinks.shift();
        }
        if (AppPlugin.pendingLinks.length > 0) {
          AppPlugin.deliverPendingLinkIfReady();
        }
      },
      error: (code: string, message: string, details: Any) => {
        if (AppPlugin.pendingLinkDeliveryId !== deliveryId) {
          return;
        }
        AppPlugin.pendingLinkDeliveryInFlight = false;
        AppPlugin.pendingLinkInFlightValue = '';
        if (
          AppPlugin.pendingLinks.length > 0 &&
          AppPlugin.pendingLinks[0] !== link
        ) {
          AppPlugin.deliverPendingLinkIfReady();
        }
        console.warn(
          `[AppPlugin] appLink delivery failed code=${code} message=${message} details=${stringifyError(details)}`,
        );
      },
      notImplemented: () => {
        if (AppPlugin.pendingLinkDeliveryId !== deliveryId) {
          return;
        }
        AppPlugin.pendingLinkDeliveryInFlight = false;
        AppPlugin.pendingLinkInFlightValue = '';
        if (
          AppPlugin.pendingLinks.length > 0 &&
          AppPlugin.pendingLinks[0] !== link
        ) {
          AppPlugin.deliverPendingLinkIfReady();
        }
        console.warn('[AppPlugin] appLink delivery not implemented by Flutter');
      },
    });
  }

  private static deliverPendingDebugVpnStartIfReady(): void {
    if (
      AppPlugin.pendingDebugVpnStarts.length === 0 ||
      !AppPlugin.pendingDebugVpnStartListenerReady ||
      AppPlugin.activeChannel == null ||
      AppPlugin.pendingDebugVpnStartDeliveryInFlight
    ) {
      return;
    }
    const pendingDebugVpnStart = AppPlugin.pendingDebugVpnStarts[0];
    if (pendingDebugVpnStart == null) {
      return;
    }
    const deliveryId = AppPlugin.pendingDebugVpnStartDeliveryId + 1;
    AppPlugin.pendingDebugVpnStartDeliveryId = deliveryId;
    AppPlugin.pendingDebugVpnStartDeliveryInFlight = true;
    AppPlugin.pendingDebugVpnStartInFlightValue = pendingDebugVpnStart;
    AppPlugin.activeChannel.invokeMethod('pendingDebugVpnStart', {
      stack: pendingDebugVpnStart.stack,
      ipv6: pendingDebugVpnStart.ipv6,
    }, {
      success: () => {
        if (AppPlugin.pendingDebugVpnStartDeliveryId !== deliveryId) {
          return;
        }
        AppPlugin.pendingDebugVpnStartDeliveryInFlight = false;
        AppPlugin.pendingDebugVpnStartInFlightValue = null;
        if (
          AppPlugin.pendingDebugVpnStarts.length > 0 &&
          AppPlugin.pendingDebugVpnStarts[0] === pendingDebugVpnStart
        ) {
          AppPlugin.pendingDebugVpnStarts.shift();
        }
        if (AppPlugin.pendingDebugVpnStarts.length > 0) {
          AppPlugin.deliverPendingDebugVpnStartIfReady();
        }
      },
      error: (code: string, message: string, details: Any) => {
        if (AppPlugin.pendingDebugVpnStartDeliveryId !== deliveryId) {
          return;
        }
        AppPlugin.pendingDebugVpnStartDeliveryInFlight = false;
        AppPlugin.pendingDebugVpnStartInFlightValue = null;
        if (
          AppPlugin.pendingDebugVpnStarts.length > 0 &&
          AppPlugin.pendingDebugVpnStarts[0] !== pendingDebugVpnStart
        ) {
          AppPlugin.deliverPendingDebugVpnStartIfReady();
        }
        console.warn(
          `[AppPlugin] pendingDebugVpnStart delivery failed code=${code} message=${message} details=${stringifyError(details)}`,
        );
      },
      notImplemented: () => {
        if (AppPlugin.pendingDebugVpnStartDeliveryId !== deliveryId) {
          return;
        }
        AppPlugin.pendingDebugVpnStartDeliveryInFlight = false;
        AppPlugin.pendingDebugVpnStartInFlightValue = null;
        if (
          AppPlugin.pendingDebugVpnStarts.length > 0 &&
          AppPlugin.pendingDebugVpnStarts[0] !== pendingDebugVpnStart
        ) {
          AppPlugin.deliverPendingDebugVpnStartIfReady();
        }
        console.warn('[AppPlugin] pendingDebugVpnStart delivery not implemented by Flutter');
      },
    });
  }

  static setPendingLink(link: string): void {
    AppPlugin.pendingLinks.push(link);
    console.info(`[AppPlugin] setPendingLink=${link}`);
    AppPlugin.deliverPendingLinkIfReady();
  }

  static getLastImportedGalleryUri(): string {
    return AppPlugin.lastImportedGalleryUri;
  }

  static getLastImportedGalleryIdentifier(): string {
    return AppPlugin.lastImportedGalleryIdentifier;
  }

  static setLastFilePickerState(state: string): void {
    AppPlugin.lastFilePickerState = state;
    console.info(`[AppPlugin] lastFilePickerState=${state}`);
  }

  static getLastFilePickerState(): string {
    return AppPlugin.lastFilePickerState;
  }

  static setPendingLinkFromWant(want: Want | undefined): void {
    const uri = (want?.uri as string | undefined) ?? '';
    if (!uri) {
      const params = want?.parameters as Record<string, Object> | undefined;
      const debugStartVpn = params?.debugStartVpn;
      if (debugStartVpn === true) {
        const stack = typeof params?.stack === 'string' && params.stack.length > 0
          ? params.stack
          : 'mixed';
        const ipv6 = params?.ipv6 === true;
        const pendingDebugVpnStart: PendingDebugVpnStart = {
          stack,
          ipv6,
        };
        AppPlugin.pendingDebugVpnStarts.push(pendingDebugVpnStart);
        console.info(
          `[AppPlugin] setPendingDebugVpnStart stack=${stack} ipv6=${ipv6}`,
        );
        AppPlugin.deliverPendingDebugVpnStartIfReady();
      }
      return;
    }
    AppPlugin.setPendingLink(uri);
  }

  private consumePendingLink(): string {
    if (
      AppPlugin.pendingLinkDeliveryInFlight &&
      AppPlugin.pendingLinkInFlightValue.length > 0 &&
      AppPlugin.pendingLinks[0] === AppPlugin.pendingLinkInFlightValue
    ) {
      return '';
    }
    const link = AppPlugin.pendingLinks.shift() ?? '';
    return link;
  }

  private consumePendingDebugVpnStart(): PendingDebugVpnStart | null {
    if (
      AppPlugin.pendingDebugVpnStartDeliveryInFlight &&
      AppPlugin.pendingDebugVpnStartInFlightValue != null &&
      AppPlugin.pendingDebugVpnStarts[0] === AppPlugin.pendingDebugVpnStartInFlightValue
    ) {
      return null;
    }
    const pending = AppPlugin.pendingDebugVpnStarts.shift() ?? null;
    if (AppPlugin.pendingDebugVpnStarts.length > 0) {
      AppPlugin.deliverPendingDebugVpnStartIfReady();
    }
    return pending;
  }

  private tryStartPendingDebugVpn(): void {
    if (AppPlugin.pendingDebugVpnStarts.length === 0) {
      return;
    }
    console.info('[AppPlugin] pending debug VPN start is ready for Flutter consumption');
  }

  getUniqueClassName(): string {
    return 'AppPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.pluginBinding = binding;
    this.applicationContext = binding.getApplicationContext();
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.abilityBinding = binding;
    this.ability = binding.getAbility();
    this.applicationContext = this.ability.context;
    this.channel = new MethodChannel(
      this.pluginBinding!.getBinaryMessenger(),
      'com.follow.clash/app',
    );
    AppPlugin.activeChannel = this.channel;
    this.channel.setMethodCallHandler(this);
    AppPlugin.deliverPendingLinkIfReady();
    AppPlugin.deliverPendingDebugVpnStartIfReady();
    this.tryStartPendingDebugVpn();
  }

  onDetachedFromAbility(): void {
    const detachedChannel = this.channel;
    if (this.channel !== null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
    AppPlugin.pendingLinkDeliveryInFlight = false;
    AppPlugin.pendingLinkInFlightValue = '';
    AppPlugin.appLinkListenerReady = false;
    AppPlugin.pendingDebugVpnStartDeliveryInFlight = false;
    AppPlugin.pendingDebugVpnStartInFlightValue = null;
    AppPlugin.pendingDebugVpnStartListenerReady = false;
    AppPlugin.pendingLinkDeliveryId += 1;
    AppPlugin.pendingDebugVpnStartDeliveryId += 1;
    this.abilityBinding = null;
    this.ability = null;
    if (AppPlugin.activeChannel === detachedChannel) {
      AppPlugin.activeChannel = null;
    }
    this.applicationContext = this.pluginBinding?.getApplicationContext() ?? null;
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.onDetachedFromAbility();
    this.pluginBinding = null;
    this.applicationContext = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    const context = this.applicationContext;
    switch (call.method) {
      case 'getAppPaths':
        if (context == null) {
          result.error('NO_CONTEXT', 'Application context unavailable', null);
          return;
        }
        result.success({
          filesDir: context.filesDir,
          cacheDir: context.cacheDir,
          tempDir: context.tempDir,
          bundleCodeDir: context.bundleCodeDir,
          codePath: context.applicationInfo.codePath,
          nativeLibraryPath: context.applicationInfo.nativeLibraryPath,
        });
        return;
      case 'consumePendingLink': {
        const link = this.consumePendingLink();
        result.success(link);
        return;
      }
      case 'updateAppLinkListenerReady': {
        AppPlugin.appLinkListenerReady = call.args === true;
        if (AppPlugin.appLinkListenerReady) {
          AppPlugin.deliverPendingLinkIfReady();
        }
        result.success(true);
        return;
      }
      case 'exitApp': {
        const abilityContext = this.ability?.context;
        if (abilityContext == null) {
          result.error('NO_ABILITY_CONTEXT', 'UI ability context unavailable', null);
          return;
        }
        void (async () => {
          try {
            await abilityContext.terminateSelf();
            result.success(true);
          } catch (error) {
            console.error(
              `[AppPlugin] exitApp failed error=${stringifyError(error)}`,
            );
            result.success(false);
          }
        })();
        return;
      }
      case 'moveTaskToBack': {
        const abilityContext = this.ability?.context as common.UIAbilityContext | undefined;
        if (abilityContext == null) {
          result.error('NO_ABILITY_CONTEXT', 'UI ability context unavailable', null);
          return;
        }
        void (async () => {
          try {
            await abilityContext.moveAbilityToBackground();
            console.info('[AppPlugin] moveTaskToBack success');
            result.success(true);
          } catch (error) {
            console.error(
              `[AppPlugin] moveTaskToBack failed error=${stringifyError(error)}`,
            );
            result.success(false);
          }
        })();
        return;
      }
      case 'startCoreChildProcess': {
        const args = call.args as Map<string, string> | null;
        const entryParams = args?.get('entryParams') ?? '';
        try {
          const probe = nativeBridge.probeCreateNativeChildProcess();
          console.info(
            `[AppPlugin] probeCreateNativeChildProcess result=${probe} lastError=${nativeBridge.lastError()}`,
          );
          const pid = nativeBridge.startCoreChildProcess(entryParams);
          if (pid <= 0) {
            console.error(
              `[AppPlugin] startCoreChildProcess failed pid=${pid}, lastError=${nativeBridge.lastError()}`,
            );
          } else {
            console.info(
              `[AppPlugin] startCoreChildProcess pid=${pid} entryParams=${entryParams}`,
            );
          }
          result.success(pid);
        } catch (error) {
          result.error(
            'START_CORE_CHILD_PROCESS_FAILED',
            stringifyError(error),
            nativeBridge.lastError(),
          );
        }
        return;
      }
      case 'startBundledCoreProcess': {
        const args = call.args as Map<string, string> | null;
        const sourcePath = args?.get('sourcePath') ?? '';
        const socketPath = args?.get('socketPath') ?? '';
        const logDirPath = args?.get('logDirPath') ?? '';
        try {
          const pid = nativeBridge.startBundledCoreProcess(
            sourcePath,
            socketPath,
            logDirPath,
          );
          if (pid <= 0) {
            console.error(
              `[AppPlugin] startBundledCoreProcess failed, lastError=${nativeBridge.lastError()}`,
            );
          }
          result.success(pid);
        } catch (error) {
          result.error(
            'START_BUNDLED_CORE_PROCESS_FAILED',
            stringifyError(error),
            nativeBridge.lastError(),
          );
        }
        return;
      }
      case 'startEmbeddedCore': {
        const args = call.args as Map<string, string> | null;
        const socketPath = args?.get('socketPath') ?? '';
        const logDirPath = args?.get('logDirPath') ?? '';
        try {
          const pid = nativeBridge.startEmbeddedCore(socketPath, logDirPath);
          if (pid <= 0) {
            console.error(
              `[AppPlugin] startEmbeddedCore failed, lastError=${nativeBridge.lastError()}`,
            );
          } else {
            console.info(
              `[AppPlugin] startEmbeddedCore pid=${pid} socketPath=${socketPath}`,
            );
          }
          result.success(pid);
        } catch (error) {
          result.error(
            'START_EMBEDDED_CORE_FAILED',
            stringifyError(error),
            nativeBridge.lastError(),
          );
        }
        return;
      }
      case 'stopTrackedCore': {
        try {
          const stopped = nativeBridge.stopTrackedCore();
          if (!stopped) {
            console.error(
              `[AppPlugin] stopTrackedCore failed, lastError=${nativeBridge.lastError()}`,
            );
          } else {
            console.info('[AppPlugin] stopTrackedCore success');
          }
          result.success(stopped);
        } catch (error) {
          result.error(
            'STOP_TRACKED_CORE_FAILED',
            stringifyError(error),
            nativeBridge.lastError(),
          );
        }
        return;
      }
      case 'invokeCore': {
        const args = call.args as Map<string, string> | null;
        const action = args?.get('action') ?? '';
        void (async () => {
          try {
            const response = await nativeBridge.invokeCoreAsync(action);
            if (!response) {
              console.error(
                `[AppPlugin] invokeCore empty result, lastError=${nativeBridge.lastError()}`,
              );
            }
            result.success(response);
        } catch (error) {
          result.error(
            'CORE_INVOKE_FAILED',
            stringifyError(error),
            nativeBridge.lastError(),
          );
        }
        })();
        return;
      }
      case 'consumeCoreEvents': {
        try {
          result.success(nativeBridge.consumeCoreEvents());
        } catch (error) {
          result.error(
            'CONSUME_CORE_EVENTS_FAILED',
            stringifyError(error),
            nativeBridge.lastError(),
          );
        }
        return;
      }
      case 'markExecutable': {
        const args = call.args as Map<string, string> | null;
        const path = args?.get('path') ?? '';
        try {
          const success = nativeBridge.chmodPath(path);
          if (!success) {
            console.error(
              `[AppPlugin] markExecutable failed, lastError=${nativeBridge.lastError()}`,
            );
          }
          result.success(success);
        } catch (error) {
          result.error(
            'MARK_EXECUTABLE_FAILED',
            stringifyError(error),
            nativeBridge.lastError(),
          );
        }
        return;
      }
      case 'startVpn': {
        const args = call.args as Map<string, Object> | null;
        const stack = (args?.get('stack') as string | undefined) ?? 'mixed';
        const ipv6 = (args?.get('ipv6') as boolean | undefined) ?? false;
        const initParamsJson =
          (args?.get('initParamsJson') as string | undefined) ?? '';
        const setupParamsJson =
          (args?.get('setupParamsJson') as string | undefined) ?? '';
        const coreSocketPath =
          (args?.get('coreSocketPath') as string | undefined) ?? '';
        void this.startVpn(
          stack,
          ipv6,
          initParamsJson,
          setupParamsJson,
          coreSocketPath,
          result,
        );
        return;
      }
      case 'stopVpn': {
        void this.stopVpn(result);
        return;
      }
      case 'getVpnRunning': {
        result.success(this.isVpnStatusRunning(this.applicationContext));
        return;
      }
      case 'consumePendingDebugVpnStart': {
        const pending = this.consumePendingDebugVpnStart();
        if (pending == null) {
          result.success(null);
          return;
        }
        result.success({
          stack: pending.stack,
          ipv6: pending.ipv6,
        });
        return;
      }
      case 'updatePendingDebugVpnStartListenerReady': {
        AppPlugin.pendingDebugVpnStartListenerReady = call.args === true;
        if (AppPlugin.pendingDebugVpnStartListenerReady) {
          AppPlugin.deliverPendingDebugVpnStartIfReady();
        }
        result.success(true);
        return;
      }
      case 'importImageToGallery': {
        const args = call.args as Map<string, string> | null;
        const path = args?.get('path') ?? '';
        const title = args?.get('title') ?? 'flclash_qr_test';
        if (context == null) {
          result.error('NO_CONTEXT', 'Application context unavailable', null);
          return;
        }
        if (!path) {
          result.error('INVALID_PATH', 'Image path is required', null);
          return;
        }
        void this.importImageToGallery(context, path, title, result);
        return;
      }
      case 'prepareGalleryTestImage': {
        const args = call.args as Map<string, string> | null;
        const path = args?.get('path') ?? '';
        const title = args?.get('title') ?? 'flclash_qr_test';
        if (context == null) {
          result.error('NO_CONTEXT', 'Application context unavailable', null);
          return;
        }
        if (!path) {
          result.error('INVALID_PATH', 'Image path is required', null);
          return;
        }
        const targetPath = `${context.filesDir}/${title}.png`;
        try {
          fs.copyFileSync(path, targetPath);
          result.success(targetPath);
        } catch (error) {
          result.error(
            'PREPARE_GALLERY_TEST_IMAGE_FAILED',
            stringifyError(error),
            null,
          );
        }
        return;
      }
      case 'writeFileToSharedDownload': {
        const args = call.args as Map<string, string> | null;
        const path = args?.get('path') ?? '';
        const fileName = args?.get('fileName') ?? 'jisu_qr_test.png';
        if (context == null) {
          result.error('NO_CONTEXT', 'Application context unavailable', null);
          return;
        }
        if (!path) {
          result.error('INVALID_PATH', 'File path is required', null);
          return;
        }
        const targetPath = `/storage/Users/currentUser/Download/${fileName}`;
        const targetUri = fileUri.getUriFromPath(targetPath);
        void (async () => {
          try {
            const bytes = readAllBytes(path);
            const targetDir = targetPath.substring(0, targetPath.lastIndexOf('/'));
            try {
              fs.accessSync(targetDir);
            } catch (_) {
              fs.mkdirSync(targetDir, true);
            }
            writeAllBytes(targetPath, bytes);
            const targetStat = fs.statSync(targetPath);
            AppPlugin.setLastFilePickerState(
              `sharedDownload:written:uri=${targetUri}:path=${targetPath}:size=${bytes.byteLength}:stat=${Number(targetStat.size)}`,
            );
            result.success(targetUri);
          } catch (error) {
            AppPlugin.setLastFilePickerState(
              `sharedDownload:error:error=${stringifyError(error)}`,
            );
            result.error(
              'WRITE_SHARED_DOWNLOAD_FAILED',
              stringifyError(error),
              null,
            );
          }
        })();
        return;
      }
      case 'getLastImportedGalleryUri': {
        result.success(AppPlugin.lastImportedGalleryUri);
        return;
      }
      case 'getLastImportedGalleryIdentifier': {
        result.success(AppPlugin.lastImportedGalleryIdentifier);
        return;
      }
      case 'getLastFilePickerState': {
        result.success(AppPlugin.lastFilePickerState);
        return;
      }
      case 'openExternalUrl': {
        const args = call.args as Map<string, string> | null;
        const url = args?.get('url') ?? '';
        const abilityContext = this.ability?.context;
        if (abilityContext == null) {
          result.error('NO_ABILITY_CONTEXT', 'UI ability context unavailable', null);
          return;
        }
        if (!url) {
          result.error('INVALID_URL', 'URL is required', null);
          return;
        }
        void (async () => {
          try {
            const want: Want = {
              action: 'ohos.want.action.viewData',
              uri: url,
              entities: ['entity.system.browsable'],
            };
            await abilityContext.startAbility(want);
            console.info(`[AppPlugin] openExternalUrl success url=${url}`);
            result.success(true);
          } catch (error) {
            console.error(
              `[AppPlugin] openExternalUrl failed url=${url} error=${stringifyError(error)}`,
            );
            result.success(false);
          }
        })();
        return;
      }
      case 'setClipboardText': {
        const args = call.args as Map<string, string> | null;
        const text = args?.get('text') ?? '';
        void (async () => {
          try {
            const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
            const systemPasteboard = pasteboard.getSystemPasteboard();
            await systemPasteboard.setData(data);
            AppPlugin.lastClipboardText = text;
            console.info(`[AppPlugin] setClipboardText success length=${text.length}`);
            result.success(true);
          } catch (error) {
            console.error(
              `[AppPlugin] setClipboardText failed error=${stringifyError(error)}`,
            );
            result.success(false);
          }
        })();
        return;
      }
      case 'getClipboardText': {
        void (async () => {
          try {
            const systemPasteboard = pasteboard.getSystemPasteboard();
            const data = await systemPasteboard.getData();
            const text: string = data.getPrimaryText();
            const resolvedText =
              text && text.length > 0 ? text : AppPlugin.lastClipboardText;
            console.info(
              `[AppPlugin] getClipboardText success length=${resolvedText.length} rawLength=${text.length}`,
            );
            result.success(resolvedText);
          } catch (error) {
            console.error(
              `[AppPlugin] getClipboardText failed error=${stringifyError(error)} fallbackLength=${AppPlugin.lastClipboardText.length}`,
            );
            result.success(AppPlugin.lastClipboardText);
          }
        })();
        return;
      }
      default:
        result.notImplemented();
        return;
      }
  }

  private async importImageToGallery(
    context: common.Context,
    path: string,
    title: string,
    result: MethodResult,
  ): Promise<void> {
    try {
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const assetUris = await helper.showAssetsCreationDialog(
        [path],
        [{
          title,
          fileNameExtension: 'png',
          photoType: photoAccessHelper.PhotoType.IMAGE,
        }],
      );
      AppPlugin.lastImportedGalleryUri = assetUris.length > 0 ? assetUris[0] : '';
      try {
        const recentPhotoInfo = await helper.getRecentPhotoInfo({
          MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
          photoSource: photoAccessHelper.PhotoSource.ALL,
        });
        AppPlugin.lastImportedGalleryIdentifier = recentPhotoInfo.identifier ?? '';
        AppPlugin.setLastFilePickerState(
          `gallery:imported:uri=${AppPlugin.lastImportedGalleryUri}:identifier=${AppPlugin.lastImportedGalleryIdentifier}`,
        );
      } catch (infoError) {
        AppPlugin.lastImportedGalleryIdentifier = '';
        AppPlugin.setLastFilePickerState(
          `gallery:imported:uri=${AppPlugin.lastImportedGalleryUri}:identifier_error=${stringifyError(infoError)}`,
        );
      }
      result.success(assetUris.length > 0 ? assetUris[0] : '');
    } catch (error) {
      result.error(
        'IMPORT_IMAGE_TO_GALLERY_FAILED',
        stringifyError(error),
        null,
      );
    }
  }

  private async startVpn(
    stack: string,
    ipv6: boolean,
    initParamsJson: string,
    setupParamsJson: string,
    coreSocketPath: string,
    result: MethodResult,
  ): Promise<void> {
    if (
      this.isVpnStatusRunning(this.ability?.context ?? this.applicationContext)
    ) {
      this.isVpnRunning = true;
      result.success(true);
      return;
    }
    const abilityContext = this.ability?.context;
    if (abilityContext == null) {
      result.error('NO_ABILITY_CONTEXT', 'UI ability context unavailable', null);
      return;
    }
    const statusPath = this.getVpnStatusPath(abilityContext);
    let ownsStartAttempt = false;
    try {
      if (this.vpnStartInFlight) {
        const status = await this.waitForVpnStatus(statusPath);
        const resolution = resolveVpnStartResult({
          startErrorMessage: '',
          status,
        });
        if (!resolution.started) {
          throw new Error(resolution.errorMessage);
        }
        this.isVpnRunning = true;
        result.success(true);
        return;
      }
      this.vpnStartInFlight = true;
      ownsStartAttempt = true;
      this.resetVpnStatus(statusPath);
      const want: Want = {
        bundleName: 'com.follow.clash',
        abilityName: 'FlClashVpnAbility',
        parameters: {
          stack,
          ipv6,
          initParamsJson,
          setupParamsJson,
          coreSocketPath,
        },
      };
      console.info(
        `[AppPlugin] startVpn stack=${stack} ipv6=${ipv6}`,
      );
      let startErrorMessage = '';
      try {
        await this.withTimeout(
          vpnExtension.startVpnExtensionAbility(want),
          3000,
          'startVpnExtensionAbility timeout',
        );
      } catch (error) {
        startErrorMessage = stringifyError(error);
      }
      const status = await this.waitForVpnStatus(statusPath);
      const resolution = resolveVpnStartResult({
        startErrorMessage,
        status,
      });
      if (!resolution.started) {
        throw new Error(resolution.errorMessage);
      }
      this.isVpnRunning = true;
      result.success(true);
    } catch (error) {
      const errorMessage = stringifyError(error);
      const normalizedMessage =
        errorMessage === '{}' ? 'vpn extension not ready' : errorMessage;
      console.error(
        `[AppPlugin] startVpn failed error=${normalizedMessage} lastError=${nativeBridge.lastError()}`,
      );
      this.isVpnRunning = false;
      result.error(
        'START_VPN_FAILED',
        normalizedMessage,
        nativeBridge.lastError(),
      );
    } finally {
      if (ownsStartAttempt) {
        this.vpnStartInFlight = false;
      }
    }
  }

  private async stopVpn(result: MethodResult): Promise<void> {
    const statusPath = this.applicationContext == null
      ? ''
      : this.getVpnStatusPath(this.applicationContext);
    const vpnRunning = this.isVpnStatusRunning(this.applicationContext);
    let currentStatus = statusPath.length > 0
      ? this.readVpnStatus(statusPath)
      : '';
    if (currentStatus.length === 0 && this.vpnStartInFlight) {
      currentStatus = await this.waitForVpnStatus(statusPath);
      if (currentStatus.startsWith('failed:')) {
        this.isVpnRunning = false;
        result.success(true);
        return;
      }
    }
    if (
      currentStatus === 'stopped' ||
      (currentStatus.length === 0 && !vpnRunning && !this.vpnStartInFlight)
    ) {
      if (currentStatus === 'stopped') {
        this.isVpnRunning = false;
      }
      result.success(true);
      return;
    }
    if (currentStatus.startsWith('failed:')) {
      if (!this.shouldRetryFailedVpnStopStatus(currentStatus)) {
        this.isVpnRunning = false;
        result.success(true);
        return;
      }
      this.resetVpnStatus(statusPath);
    }
    this.isVpnRunning = true;
    try {
      const want: Want = {
        bundleName: 'com.follow.clash',
        abilityName: 'FlClashVpnAbility',
      };
      let stopErrorMessage = '';
      try {
        await this.withTimeout(
          vpnExtension.stopVpnExtensionAbility(want),
          3000,
          'stopVpnExtensionAbility timeout',
        );
      } catch (error) {
        stopErrorMessage = stringifyError(error);
      }
      const status = await this.waitForVpnStoppedStatus(statusPath);
      const resolution = resolveVpnStopResult({
        stopErrorMessage,
        status,
      });
      // A status that is still 'started' after stopVpnExtensionAbility + the
      // wait timeout means the VPN extension was killed uncleanly (e.g. the
      // process died / was force-stopped) and can no longer transition its
      // status file to 'stopped' — not that it is actively refusing to stop.
      // FlClashVpnAbility is a system-managed singleton VPN, so reconcile the
      // stale state to stopped here; otherwise the leftover 'started' blocks
      // every subsequent startVpn (isVpnStatusRunning short-circuits) and
      // stopVpn (waitForVpnStoppedStatus never sees 'stopped').
      if (!resolution.stopped && status === 'started') {
        this.resetVpnStatus(statusPath);
        this.isVpnRunning = false;
        result.success(true);
        return;
      }
      if (!resolution.stopped) {
        throw new Error(resolution.errorMessage);
      }
      this.isVpnRunning = false;
      result.success(true);
    } catch (error) {
      const cleanupErrors: string[] = [];
      try {
        const stopped = nativeBridge.stopTun();
        if (!stopped) {
          cleanupErrors.push(`stopTun failed: ${nativeBridge.lastError()}`);
        }
      } catch (cleanupError) {
        cleanupErrors.push(`stopTun failed: ${stringifyError(cleanupError)}`);
      }
      try {
        const stopped = nativeBridge.stopTrackedCore();
        if (!stopped) {
          cleanupErrors.push(`stopTrackedCore failed: ${nativeBridge.lastError()}`);
        }
      } catch (cleanupError) {
        cleanupErrors.push(
          `stopTrackedCore failed: ${stringifyError(cleanupError)}`,
        );
      }
      const errorMessage = cleanupErrors.length > 0
        ? `${stringifyError(error)} | ${cleanupErrors.join(' | ')}`
        : stringifyError(error);
      console.error(
        `[AppPlugin] stopVpn failed error=${errorMessage} lastError=${nativeBridge.lastError()}`,
      );
      if (cleanupErrors.length > 0) {
        this.isVpnRunning = true;
      } else {
        this.isVpnRunning = false;
      }
      result.error(
        'STOP_VPN_FAILED',
        errorMessage,
        nativeBridge.lastError(),
      );
    }
  }
}
