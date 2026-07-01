import {
  AbilityPluginBinding,
  BinaryMessenger,
  FlutterPlugin,
  FlutterPluginBinding,
  Log,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import { UIAbility } from '@kit.AbilityKit';

import { FilePickerDelegate } from './FilePickerDelegate';
import { FilePickerUtils } from './FilePickerUtils';

const CHANNEL = 'miguelruivo.flutter.plugins.filepicker';
const TAG = 'FilePickerPlugin';

export default class FilePickerPlugin implements FlutterPlugin, MethodCallHandler {
  private pluginBinding: FlutterPluginBinding | null = null;
  private abilityBinding: AbilityPluginBinding | null = null;
  private channel: MethodChannel | null = null;
  private ability: UIAbility | null = null;
  private delegate: FilePickerDelegate | null = null;

  getUniqueClassName(): string {
    return 'FilePickerPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.pluginBinding = binding;
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.onDetachedFromAbility();
    this.pluginBinding = null;
  }

  onDetachedFromAbility(): void {
    this.delegate?.cancelPendingResult(
      'no_activity',
      'File picker ability detached before completion',
    );
    if (this.channel !== null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
    this.abilityBinding = null;
    this.ability = null;
    this.delegate = null;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.abilityBinding = binding;
    this.ability = binding.getAbility();
    this.delegate = new FilePickerDelegate(this.ability);
    this.setup(this.pluginBinding?.getBinaryMessenger() as BinaryMessenger);
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    Log.i(TAG, `onMethodCall method=${call.method}`);
    if (this.ability === null || this.delegate === null) {
      result.error('no_activity', 'file picker plugin requires a foreground ability', null);
      return;
    }
    const args = (call.args as Map<string, Object>) ?? new Map<string, Object>();
    if (call.method === 'pickForFlClash') {
      const allowMultipleSelection =
        (args.get('allowMultipleSelection') as boolean | undefined) ?? false;
      const allowedExtensions = (args.get('allowedExtensions') as Array<string> | undefined) ?? [];
      const initialDirectory = (args.get('initialDirectory') as string | undefined) ?? '';
      const normalizedExtensions = allowedExtensions.map((item) => item.toLowerCase());
      const imageExtensions = ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp', 'heic'];
      const fileType =
        normalizedExtensions.length > 0 &&
          normalizedExtensions.every((item) => imageExtensions.includes(item))
        ? 'image'
        : allowedExtensions.length > 0
        ? 'custom'
        : 'any';
      this.delegate.pickUrisOnly(
        fileType,
        allowMultipleSelection,
        allowedExtensions,
        initialDirectory,
        result,
      );
      return;
    }
    if (call.method === 'readForFlClash') {
      const uri = (args.get('uri') as string | undefined) ?? '';
      const withData = (args.get('withData') as boolean | undefined) ?? false;
      void this.delegate.readPickedFile(uri, withData, result);
      return;
    }
    if (call.method === 'clear') {
      result.success(FilePickerUtils.clearCache(this.ability.context));
      return;
    }
    if (call.method === 'save') {
      const fileName = (args.get('fileName') as string | undefined) ?? 'file';
      const initialDirectory = (args.get('initialDirectory') as string | undefined) ?? '';
      const allowedExtensions = (args.get('allowedExtensions') as Array<string> | undefined) ?? [];
      const bytes = (args.get('bytes') as Uint8Array | undefined) ?? new Uint8Array();
      this.delegate.saveFile([fileName], initialDirectory, allowedExtensions, bytes, result);
      return;
    }

    const allowMultipleSelection =
      (args.get('allowMultipleSelection') as boolean | undefined) ?? false;
    const allowedExtensions = (args.get('allowedExtensions') as Array<string> | undefined) ?? [];
    const withData = (args.get('withData') as boolean | undefined) ?? false;
    this.delegate.startFileExplorer(
      call.method,
      allowMultipleSelection,
      withData,
      allowedExtensions,
      result,
    );
  }

  private setup(messenger: BinaryMessenger): void {
    this.channel = new MethodChannel(messenger, CHANNEL);
    this.channel.setMethodCallHandler(this);
  }
}
