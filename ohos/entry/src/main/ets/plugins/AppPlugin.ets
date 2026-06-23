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
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';

interface NativeBridge {
  invokeCore(action: string): string;
  consumeCoreEvents(): string;
  chmodPath(path: string): boolean;
  probeCreateNativeChildProcess(): number;
  startCoreChildProcess(entryParams: string): number;
  startBundledCoreProcess(sourcePath: string, socketPath: string): number;
  startTun(fd: number, stack: string, address: string, dns: string): boolean;
  stopTun(): boolean;
  lastError(): string;
}

const nativeBridge = loadNativeModule('libentry.so') as NativeBridge;
const VPN_STATUS_FILE_NAME = 'flclash-vpn-status.txt';

function stringifyError(error: Object): string {
  try {
    const value = JSON.stringify(error);
    if (value && value !== 'undefined') {
      return value;
    }
  } catch (_) {}
  return `${error}`;
}

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
  private static pendingLink: string = '';
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

  private async waitForVpnStatus(path: string): Promise<string> {
    for (let index = 0; index < 30; index += 1) {
      const status = this.readVpnStatus(path);
      if (
        status === 'started' ||
        status === 'stopped' ||
        status.startsWith('failed:')
      ) {
        return status;
      }
      await new Promise<void>((resolve) => setTimeout(resolve, 100));
    }
    return this.readVpnStatus(path);
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

  static setPendingLink(link: string): void {
    AppPlugin.pendingLink = link;
    console.info(`[AppPlugin] setPendingLink=${link}`);
    AppPlugin.activeChannel?.invokeMethod('appLink', link);
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
      return;
    }
    AppPlugin.setPendingLink(uri);
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
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    const detachedChannel = this.channel;
    if (this.channel !== null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
    this.pluginBinding = null;
    this.abilityBinding = null;
    this.ability = null;
    if (AppPlugin.activeChannel === detachedChannel) {
      AppPlugin.activeChannel = null;
    }
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
        const link = AppPlugin.pendingLink;
        AppPlugin.pendingLink = '';
        result.success(link);
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
            console.error(`[AppPlugin] exitApp failed error=${error}`);
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
            console.error(`[AppPlugin] moveTaskToBack failed error=${error}`);
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
            `${error}`,
            nativeBridge.lastError(),
          );
        }
        return;
      }
      case 'startBundledCoreProcess': {
        const args = call.args as Map<string, string> | null;
        const sourcePath = args?.get('sourcePath') ?? '';
        const socketPath = args?.get('socketPath') ?? '';
        try {
          const pid = nativeBridge.startBundledCoreProcess(
            sourcePath,
            socketPath,
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
            `${error}`,
            nativeBridge.lastError(),
          );
        }
        return;
      }
      case 'invokeCore': {
        const args = call.args as Map<string, string> | null;
        const action = args?.get('action') ?? '';
        try {
          const response = nativeBridge.invokeCore(action);
          if (!response) {
            console.error(
              `[AppPlugin] invokeCore empty result, lastError=${nativeBridge.lastError()}`,
            );
          }
          result.success(response);
        } catch (error) {
          result.error(
            'CORE_INVOKE_FAILED',
            `${error}`,
            nativeBridge.lastError(),
          );
        }
        return;
      }
      case 'consumeCoreEvents': {
        try {
          result.success(nativeBridge.consumeCoreEvents());
        } catch (error) {
          result.error(
            'CONSUME_CORE_EVENTS_FAILED',
            `${error}`,
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
            `${error}`,
            nativeBridge.lastError(),
          );
        }
        return;
      }
      case 'startVpn': {
        const args = call.args as Map<string, Object> | null;
        const stack = (args?.get('stack') as string | undefined) ?? 'mixed';
        const ipv6 = (args?.get('ipv6') as boolean | undefined) ?? false;
        const allowBypass =
          (args?.get('allowBypass') as boolean | undefined) ?? true;
        void this.startVpn(stack, ipv6, allowBypass, result);
        return;
      }
      case 'stopVpn': {
        void this.stopVpn(result);
        return;
      }
      case 'getVpnRunning': {
        result.success(this.isVpnRunning);
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
          result.error('PREPARE_GALLERY_TEST_IMAGE_FAILED', `${error}`, null);
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
            AppPlugin.setLastFilePickerState(`sharedDownload:error:error=${error}`);
            result.error('WRITE_SHARED_DOWNLOAD_FAILED', `${error}`, null);
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
            console.error(`[AppPlugin] openExternalUrl failed url=${url} error=${error}`);
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
            console.error(`[AppPlugin] setClipboardText failed error=${error}`);
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
              `[AppPlugin] getClipboardText failed error=${error} fallbackLength=${AppPlugin.lastClipboardText.length}`,
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
          `gallery:imported:uri=${AppPlugin.lastImportedGalleryUri}:identifier_error=${infoError}`,
        );
      }
      result.success(assetUris.length > 0 ? assetUris[0] : '');
    } catch (error) {
      result.error('IMPORT_IMAGE_TO_GALLERY_FAILED', `${error}`, null);
    }
  }

  private async startVpn(
    stack: string,
    ipv6: boolean,
    allowBypass: boolean,
    result: MethodResult,
  ): Promise<void> {
    if (this.isVpnRunning) {
      result.success(true);
      return;
    }
    const abilityContext = this.ability?.context;
    if (abilityContext == null) {
      result.error('NO_ABILITY_CONTEXT', 'UI ability context unavailable', null);
      return;
    }
    try {
      const statusPath = this.getVpnStatusPath(abilityContext);
      this.resetVpnStatus(statusPath);
      const want: Want = {
        bundleName: 'com.follow.clash',
        abilityName: 'FlClashVpnAbility',
        parameters: {
          stack,
          ipv6,
          allowBypass,
        },
      };
      console.info(
        `[AppPlugin] startVpn stack=${stack} ipv6=${ipv6} allowBypass=${allowBypass}`,
      );
      await this.withTimeout(
        vpnExtension.startVpnExtensionAbility(want),
        3000,
        'startVpnExtensionAbility timeout',
      );
      const status = await this.waitForVpnStatus(statusPath);
      if (status !== 'started') {
        throw new Error(
          status
            ? `vpn extension not ready: ${status}`
            : 'vpn extension not ready',
        );
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
    }
  }

  private async stopVpn(result: MethodResult): Promise<void> {
    if (!this.isVpnRunning) {
      result.success(true);
      return;
    }
    try {
      const statusPath = this.getVpnStatusPath(this.applicationContext!);
      const want: Want = {
        bundleName: 'com.follow.clash',
        abilityName: 'FlClashVpnAbility',
      };
      await vpnExtension.stopVpnExtensionAbility(want);
      this.resetVpnStatus(statusPath);
      this.isVpnRunning = false;
      result.success(true);
    } catch (error) {
      console.error(
        `[AppPlugin] stopVpn failed error=${stringifyError(error)} lastError=${nativeBridge.lastError()}`,
      );
      try {
        nativeBridge.stopTun();
      } catch (_) {}
      this.isVpnRunning = false;
      result.error(
        'STOP_VPN_FAILED',
        stringifyError(error),
        nativeBridge.lastError(),
      );
    }
  }
}
