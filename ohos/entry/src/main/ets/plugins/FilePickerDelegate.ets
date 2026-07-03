import { common, UIAbility } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { EventSink, Log, MethodResult } from '@ohos/flutter_ohos';

import AppPlugin from './AppPlugin';
import { stringifyError } from './error_utils';
import {
  decodePickedFileName,
  FilePickerInfo,
  FilePickerResultMap,
  FilePickerUriMap,
} from './FilePickerInfo';
import { FilePickerUtils } from './FilePickerUtils';

const TAG = 'FilePickerDelegate';
type FilePickerPayload = FilePickerResultMap | FilePickerUriMap;

export class FilePickerDelegate {
  private pendingResult: MethodResult | null = null;
  private eventSink: EventSink | null = null;
  private ability: UIAbility;
  private fileType: string = '';
  private allowMultiple: boolean = false;
  private withData: boolean = false;
  private allowedExtensions: string[] = [];

  constructor(ability: UIAbility) {
    this.ability = ability;
  }

  startFileExplorer(
    fileType: string,
    allowMultiple: boolean,
    withData: boolean,
    allowedExtensions: string[] | null | undefined,
    result: MethodResult,
  ): void {
    if (this.pendingResult !== null) {
      result.error('already_active', 'File picker is already active', null);
      return;
    }
    this.pendingResult = result;
    this.fileType = fileType;
    this.allowMultiple = allowMultiple;
    this.withData = withData;
    this.allowedExtensions = allowedExtensions ?? [];
    this.dispatchEventStatus(true);
    this.openPicker();
  }

  pickUrisOnly(
    fileType: string,
    allowMultiple: boolean,
    allowedExtensions: string[] | null | undefined,
    initialDirectory: string | null | undefined,
    result: MethodResult,
  ): void {
    Log.i(TAG, `pickUrisOnly fileType=${fileType} allowMultiple=${allowMultiple}`);
    AppPlugin.setLastFilePickerState(
      `pickUrisOnly:start:fileType=${fileType}:allowMultiple=${allowMultiple}:initialDirectory=${initialDirectory ?? ''}:extensions=${JSON.stringify(allowedExtensions ?? [])}`,
    );
    if (this.pendingResult !== null) {
      result.error('already_active', 'File picker is already active', null);
      return;
    }
    this.pendingResult = result;
    this.fileType = fileType;
    this.allowMultiple = allowMultiple;
    this.withData = false;
    this.allowedExtensions = allowedExtensions ?? [];
    this.openPickerUrisOnly(initialDirectory ?? '');
  }

  async readPickedFile(uri: string, withData: boolean, result: MethodResult): Promise<void> {
    const context = this.ability.context as common.UIAbilityContext;
    try {
      const file = await FilePickerUtils.openFileStream(context, uri, withData);
      if (file == null) {
        result.error('unknown_path', 'Failed to retrieve file path', null);
        return;
      }
      result.success(file.toMap());
    } catch (error) {
      Log.e(TAG, `readPickedFile failed: uri=${uri}, error=${stringifyError(error)}`);
      result.error('read_failed', stringifyError(error), null);
    }
  }

  saveFile(
    fileNames: string[],
    initialDirectory: string,
    allowedExtensions: string[] | null | undefined,
    bytes: Uint8Array,
    result: MethodResult,
  ): void {
    if (this.pendingResult !== null) {
      result.error('already_active', 'File picker is already active', null);
      return;
    }
    if (!initialDirectory) {
      result.error('invalid_directory', 'Save directory is required on HarmonyOS', null);
      return;
    }
    this.pendingResult = result;
    const pendingResult = result;
    const context = this.ability.context as common.UIAbilityContext;
    const documentPicker = new picker.DocumentViewPicker(context);
    const options = new picker.DocumentSaveOptions();
    options.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
    options.newFileNames = fileNames;
    options.defaultFilePathUri = initialDirectory;
    if (allowedExtensions && allowedExtensions.length > 0) {
      options.fileSuffixChoices = allowedExtensions;
    }
    documentPicker.save(options)
      .then((saveResult: Array<string>) => {
        if (!this.isPendingResultActive(pendingResult)) {
          return;
        }
        if (!saveResult || saveResult.length === 0) {
          this.finishWithError('cancelled', 'Save cancelled');
          return;
        }
        const decodedName = decodePickedFileName(fileNames[0]);
        const finalPath = saveResult[0].endsWith(decodedName)
          ? saveResult[0]
          : `${saveResult[0]}/${decodedName}`;
        FilePickerUtils.writeBytesToSavePath(bytes, finalPath);
        this.finishWithSavePath(finalPath);
      })
      .catch((error: BusinessError) => {
        if (!this.isPendingResultActive(pendingResult)) {
          return;
        }
        this.finishWithError(String(error.code), error.message);
      });
  }

  setEventHandler(eventSink: EventSink): void {
    this.eventSink = eventSink;
  }

  cancelPendingResult(code: string, message: string): void {
    if (this.pendingResult === null) {
      return;
    }
    this.finishWithError(code, message);
  }

  private isPendingResultActive(result: MethodResult | null): boolean {
    return result !== null && this.pendingResult === result;
  }

  private openPicker(): void {
    const pendingResult = this.pendingResult;
    const context = this.ability.context as common.UIAbilityContext;
    const documentPicker = new picker.DocumentViewPicker(context);
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = this.allowMultiple ? 999 : 1;
    if (this.fileType === 'dir') {
      options.selectMode = 1;
    }
    if (this.fileType === 'custom' && this.allowedExtensions.length > 0) {
      options.fileSuffixFilters = this.allowedExtensions.map((item) =>
        item.startsWith('.') ? item : `.${item}`,
      );
    }
    documentPicker.select(options)
      .then((uris: Array<string>) => {
        setTimeout(() => {
          if (pendingResult === null || !this.isPendingResultActive(pendingResult)) {
            return;
          }
          void this.handlePickedUris(pendingResult, uris);
        }, 300);
      })
      .catch((error: BusinessError) => {
        if (!this.isPendingResultActive(pendingResult)) {
          return;
        }
        Log.e(TAG, `DocumentViewPicker.select failed: ${stringifyError(error)}`);
        this.finishWithError(String(error.code), error.message);
      });
  }

  private openPickerUrisOnly(initialDirectory: string): void {
    const pendingResult = this.pendingResult;
    Log.i(TAG, 'openPickerUrisOnly begin');
    const context = this.ability.context as common.UIAbilityContext;
    const documentPicker = new picker.DocumentViewPicker(context);
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = this.allowMultiple ? 999 : 1;
    if (initialDirectory) {
      options.defaultFilePathUri = initialDirectory;
    }
    if (this.fileType === 'dir') {
      options.selectMode = 1;
    }
    if (this.fileType === 'custom' && this.allowedExtensions.length > 0) {
      options.fileSuffixFilters = this.allowedExtensions.map((item) =>
        item.startsWith('.') ? item : `.${item}`,
      );
    }
    documentPicker.select(options)
      .then(async (uris: Array<string>) => {
        if (!this.isPendingResultActive(pendingResult)) {
          return;
        }
        Log.i(TAG, `openPickerUrisOnly success count=${uris?.length ?? 0}`);
        AppPlugin.setLastFilePickerState(
          `documentPicker:success:count=${uris?.length ?? 0}:uris=${JSON.stringify(uris ?? [])}`,
        );
        if (!uris || uris.length === 0) {
          this.finishWithError('cancelled', 'No file selected');
          return;
        }
        for (const uri of uris) {
          await FilePickerUtils.prepareReadPermission(uri);
        }
        const files: Array<FilePickerPayload> = [];
        for (const uri of uris) {
          const rawName = uri.substring(uri.lastIndexOf('/') + 1);
          const decodedName = decodePickedFileName(rawName);
          files.push(new FilePickerInfo('', decodedName, 0, new Uint8Array(), uri).toUriMap());
        }
        this.finishWithSuccess(files);
      })
      .catch((error: BusinessError) => {
        if (!this.isPendingResultActive(pendingResult)) {
          return;
        }
        Log.e(TAG, `DocumentViewPicker.select uris-only failed: ${stringifyError(error)}`);
        AppPlugin.setLastFilePickerState(
          `documentPicker:error:code=${error.code}:message=${error.message}`,
        );
        this.finishWithError(String(error.code), error.message);
      });
  }

  private async handlePickedUris(result: MethodResult, uris: Array<string>): Promise<void> {
    if (!this.isPendingResultActive(result)) {
      return;
    }
    if (!uris || uris.length === 0) {
      this.finishWithError('cancelled', 'No file selected');
      return;
    }
    const context = this.ability.context as common.UIAbilityContext;
    const files: Array<FilePickerPayload> = [];
    for (const uri of uris) {
      if (!this.isPendingResultActive(result)) {
        return;
      }
      try {
        const file = await FilePickerUtils.openFileStream(context, uri, this.withData);
        if (file) {
          files.push(file.toMap());
        }
      } catch (error) {
        Log.e(TAG, `handlePickedUris failed: uri=${uri}, error=${stringifyError(error)}`);
        this.finishWithError('read_failed', stringifyError(error));
        return;
      }
    }
    if (files.length === 0) {
      this.finishWithError('unknown_path', 'Failed to retrieve file path');
      return;
    }
    this.finishWithSuccess(files);
  }

  private dispatchEventStatus(status: boolean): void {
    if (this.eventSink === null || this.fileType === 'dir') {
      return;
    }
    this.eventSink.success(status);
  }

  private finishWithSuccess(files: Array<FilePickerPayload>): void {
    if (this.pendingResult === null) {
      return;
    }
    this.dispatchEventStatus(false);
    AppPlugin.setLastFilePickerState(
      `finish:success:files=${JSON.stringify(files)}`,
    );
    this.pendingResult?.success(files);
    this.pendingResult = null;
  }

  private finishWithSavePath(path: string): void {
    if (this.pendingResult === null) {
      return;
    }
    this.dispatchEventStatus(false);
    this.pendingResult?.success(path);
    this.pendingResult = null;
  }

  private finishWithError(code: string, message: string): void {
    if (this.pendingResult === null) {
      return;
    }
    this.dispatchEventStatus(false);
    AppPlugin.setLastFilePickerState(`finish:error:code=${code}:message=${message}`);
    this.pendingResult?.error(code, message, null);
    this.pendingResult = null;
  }
}
