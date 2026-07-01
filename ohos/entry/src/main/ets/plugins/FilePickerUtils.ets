import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs, fileShare } from '@kit.CoreFileKit';
import { Log } from '@ohos/flutter_ohos';

import AppPlugin from './AppPlugin';
import { decodePickedFileName, FilePickerInfo, FilePickerInfoBuilder } from './FilePickerInfo';
import { stringifyError } from './error_utils';

const TAG = 'FilePickerUtils';
const READ_CHUNK_SIZE = 64 * 1024;

function fileNameFromUri(uri: string): string {
  return uri.substring(uri.lastIndexOf('/') + 1);
}

function replaceFileName(path: string, from: string, to: string): string {
  return path.replace(from, to);
}

function ensureDir(path: string): void {
  try {
    fs.accessSync(path);
  } catch (_) {
    const parts = path.split('/').filter((item) => item.length > 0);
    let current = path.startsWith('/') ? '/' : '';
    for (const part of parts) {
      current = current === '/' ? `/${part}` : `${current}/${part}`;
      try {
        fs.accessSync(current);
      } catch (_) {
        fs.mkdirSync(current);
      }
    }
  }
}

function readPolicy(uri: string): fileShare.PolicyInfo {
  return {
    uri,
    operationMode: fileShare.OperationMode.READ_MODE,
  };
}

function documentUriToPath(uri: string): string | null {
  const prefix = 'file://docs/';
  if (!uri.startsWith(prefix)) {
    return null;
  }
  return `/${uri.substring(prefix.length)}`;
}

declare type DynamicObject = ESObject;
declare type OpenFileMethod = (uri: string, mode: string) => Promise<number>;

function describeError(error: Object): string {
  const value = error as BusinessError;
  return `code=${String(value.code)}, message=${String(value.message)}, raw=${stringifyError(error)}`;
}

export class FilePickerUtils {
  private static toWriteBuffer(bytes: Uint8Array): ArrayBuffer {
    return bytes.byteOffset === 0 && bytes.byteLength === bytes.buffer.byteLength
      ? bytes.buffer
      : bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
  }

  private static resolveWritableCacheRoot(context: common.UIAbilityContext): string {
    const candidates: Array<string> = [
      context.filesDir,
      context.tempDir,
      context.cacheDir,
    ];
    for (const candidate of candidates) {
      try {
        const cacheRoot = `${candidate}/file_picker`;
        ensureDir(cacheRoot);
        const probePath = `${cacheRoot}/.write_probe`;
        const probe = fs.openSync(
          probePath,
          fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE,
        );
        fs.closeSync(probe);
        try {
          fs.unlinkSync(probePath);
        } catch (_) {}
        return cacheRoot;
      } catch (_) {}
    }
    const fallbackCacheRoot = `${context.filesDir}/file_picker`;
    ensureDir(fallbackCacheRoot);
    return fallbackCacheRoot;
  }

  static async prepareReadPermission(uri: string): Promise<void> {
    const policy = readPolicy(uri);
    try {
      const persisted = await fileShare.checkPersistentPermission([policy]);
      if (persisted.length === 0 || !persisted[0]) {
        await fileShare.persistPermission([policy]);
      }
      await fileShare.activatePermission([policy]);
    } catch (error) {
      Log.e(TAG, `prepareReadPermission failed: uri=${uri}, error=${describeError(error as Object)}`);
    }
  }

  private static copyUriToPath(uri: string, targetPath: string): string {
    fs.copyFileSync(uri, targetPath);
    return `copyFileSync:path:${targetPath}`;
  }

  private static writeChunk(targetFd: number, buffer: ArrayBuffer, size: number): void {
    let remaining = size;
    let pending = size === buffer.byteLength ? buffer : buffer.slice(0, size);
    while (remaining > 0) {
      const written = fs.writeSync(targetFd, pending);
      if (written <= 0) {
        throw new Error(`Failed to write copied file chunk: written=${written}`);
      }
      remaining -= written;
      if (remaining > 0) {
        pending = pending.slice(written);
      }
    }
  }

  private static copyFdToTarget(sourceFd: number, targetFd: number): void {
    let totalRead = 0;
    while (true) {
      const chunkBuffer = new ArrayBuffer(READ_CHUNK_SIZE);
      const readSize = fs.readSync(sourceFd, chunkBuffer);
      if (readSize <= 0) {
        AppPlugin.setLastFilePickerState(`read:copy-fd-finished:bytes=${totalRead}:lastRead=${readSize}`);
        break;
      }
      totalRead += readSize;
      FilePickerUtils.writeChunk(targetFd, chunkBuffer, readSize);
    }
  }

  private static async copySourceToTarget(
    context: common.UIAbilityContext,
    uri: string,
    targetFd: number,
  ): Promise<string> {
    const errors: Array<string> = [];
    const translatedPath = documentUriToPath(uri);

    if (translatedPath) {
      try {
        AppPlugin.setLastFilePickerState(`read:translated-path-attempt:path=${translatedPath}`);
        const source = fs.openSync(translatedPath, fs.OpenMode.READ_ONLY);
        try {
          FilePickerUtils.copyFdToTarget(source.fd, targetFd);
          return `translatedPath:${translatedPath}`;
        } finally {
          fs.closeSync(source);
        }
      } catch (error) {
        AppPlugin.setLastFilePickerState(
          `read:translated-path-failed:path=${translatedPath}:error=${stringifyError(error)}`,
        );
        errors.push(`translatedPath(${translatedPath}): ${stringifyError(error)}`);
      }
    }

    const openFile = (context as DynamicObject).openFile as OpenFileMethod | undefined;
    AppPlugin.setLastFilePickerState(`read:context-openFile:${openFile ? 'available' : 'missing'}`);
    for (const mode of ['r', 'rw']) {
      let sourceFd: number | null = null;
      try {
        if (!openFile) {
          throw new Error('context.openFile unavailable');
        }
        sourceFd = await openFile(uri, mode);
        AppPlugin.setLastFilePickerState(`read:context-openFile-fd:mode=${mode}:fd=${sourceFd}`);
        FilePickerUtils.copyFdToTarget(sourceFd, targetFd);
        return `context.openFile:${mode}`;
      } catch (error) {
        AppPlugin.setLastFilePickerState(
          `read:context-openFile-failed:mode=${mode}:error=${stringifyError(error)}`,
        );
        errors.push(`context.openFile(${mode}): ${stringifyError(error)}`);
      } finally {
        if (sourceFd !== null) {
          try {
            fs.closeSync(sourceFd);
          } catch (_) {}
        }
      }
    }

    for (const mode of [fs.OpenMode.READ_ONLY, fs.OpenMode.READ_WRITE]) {
      let source: fs.File | null = null;
      try {
        source = fs.openSync(uri, mode);
        FilePickerUtils.copyFdToTarget(source.fd, targetFd);
        return `openSync:${mode}`;
      } catch (error) {
        errors.push(`openSync(${mode}): ${stringifyError(error)}`);
      } finally {
        if (source) {
          fs.closeSync(source);
        }
      }
    }
    Log.e(TAG, `copySourceToTarget failed: uri=${uri}, attempts=${errors.join(' || ')}`);
    throw new Error(errors.join(' | '));
  }

  private static readBytes(path: string): Uint8Array {
    let expectedSize = 0;
    try {
      const stat = fs.statSync(path);
      expectedSize = Number(stat.size);
    } catch (error) {
      Log.e(TAG, `readBytes statSync failed: path=${path}, error=${describeError(error as Object)}`);
      throw new Error(stringifyError(error));
    }
    if (expectedSize <= 0) {
      return new Uint8Array();
    }

    let file: fs.File;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    } catch (error) {
      Log.e(TAG, `readBytes openSync failed: path=${path}, error=${describeError(error as Object)}`);
      throw new Error(stringifyError(error));
    }
    try {
      const output = new Uint8Array(expectedSize);
      let totalRead = 0;
      while (totalRead < expectedSize) {
        const chunkSize = Math.min(expectedSize - totalRead, READ_CHUNK_SIZE);
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

  private static writeBytesToLocalPath(path: string, bytes: Uint8Array): void {
    try {
      fs.unlinkSync(path);
    } catch (_) {}
    const target = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
    try {
      const output = FilePickerUtils.toWriteBuffer(bytes);
      FilePickerUtils.writeChunk(target.fd, output, output.byteLength);
    } finally {
      fs.closeSync(target);
    }
  }

  private static clearCacheFiles(cacheRoot: string): void {
    const fileNames = fs.listFileSync(cacheRoot);
    for (const fileName of fileNames) {
      try {
        fs.unlinkSync(`${cacheRoot}/${fileName}`);
      } catch (_) {}
    }
  }

  static async openFileStream(
    context: common.UIAbilityContext,
    uri: string,
    withData: boolean,
  ): Promise<FilePickerInfo | null> {
    const builder = new FilePickerInfoBuilder();
    const originalName = fileNameFromUri(uri);
    const decodedName = decodePickedFileName(originalName);
    const cacheRoot = FilePickerUtils.resolveWritableCacheRoot(context);

    let target: fs.File | null = null;
    let copiedFrom = uri;

    try {
      AppPlugin.setLastFilePickerState(`read:start:uri=${uri}:withData=${withData}:cacheRoot=${cacheRoot}`);
      await FilePickerUtils.prepareReadPermission(uri);
      AppPlugin.setLastFilePickerState(`read:permission-ready:uri=${uri}`);
      const finalUri = replaceFileName(uri, originalName, decodedName);
      const tempTargetPath = `${cacheRoot}/picked_file.tmp`;
      try {
        fs.unlinkSync(tempTargetPath);
      } catch (_) {}
      try {
        copiedFrom = FilePickerUtils.copyUriToPath(uri, tempTargetPath);
        AppPlugin.setLastFilePickerState(`read:copy-direct-success:uri=${uri}:target=${tempTargetPath}`);
      } catch (copyError) {
        AppPlugin.setLastFilePickerState(
          `read:copy-direct-failed:uri=${uri}:error=${stringifyError(copyError)}`,
        );
        AppPlugin.setLastFilePickerState(`read:target-open-attempt:target=${tempTargetPath}`);
        try {
          target = fs.openSync(
            tempTargetPath,
            fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE,
          );
        } catch (targetOpenError) {
          AppPlugin.setLastFilePickerState(
            `read:target-open-failed:target=${tempTargetPath}:error=${stringifyError(targetOpenError)}`,
          );
          throw new Error(stringifyError(targetOpenError));
        }
        AppPlugin.setLastFilePickerState(`read:target-open-success:target=${tempTargetPath}`);
        copiedFrom = await FilePickerUtils.copySourceToTarget(
          context,
          uri,
          target.fd,
        );
        AppPlugin.setLastFilePickerState(`read:fallback-copy-success:mode=${copiedFrom}:target=${tempTargetPath}`);
        fs.closeSync(target);
        target = null;
      }
      const bytes = FilePickerUtils.readBytes(tempTargetPath);
      AppPlugin.setLastFilePickerState(`read:read-bytes-success:path=${tempTargetPath}:size=${bytes.byteLength}`);

      if (withData) {
        builder
          .withPath('')
          .withName(decodedName)
          .withSize(bytes.byteLength)
          .withData(bytes)
          .withUri(finalUri);
        return builder.build();
      }
      const finalPath = replaceFileName(tempTargetPath, originalName, decodedName);
      if (finalPath !== tempTargetPath) {
        try {
          fs.unlinkSync(finalPath);
        } catch (_) {}
        fs.renameSync(tempTargetPath, finalPath);
      }
      builder
        .withPath(finalPath)
        .withName(decodedName)
        .withSize(bytes.byteLength)
        .withUri(finalUri);
      return builder.build();
    } catch (error) {
      AppPlugin.setLastFilePickerState(
        `read:error:uri=${uri}:copiedFrom=${copiedFrom}:error=${stringifyError(error)}`,
      );
      Log.e(
        TAG,
        `openFileStream failed: uri=${uri}, copiedFrom=${copiedFrom}, originalName=${originalName}, decodedName=${decodedName}, error=${stringifyError(error)}`,
      );
      return null;
    } finally {
      try {
        if (target) {
          fs.closeSync(target);
        }
      } catch (_) {}
    }
  }

  static clearCache(context: common.UIAbilityContext): boolean {
    const candidates: Array<string> = [
      context.filesDir,
      context.tempDir,
      context.cacheDir,
    ];
    let hadCleanupFailure = false;
    try {
      for (const candidate of candidates) {
        const cacheRoot = `${candidate}/file_picker`;
        try {
          fs.accessSync(cacheRoot);
        } catch (_) {
          continue;
        }
        try {
          FilePickerUtils.clearCacheFiles(cacheRoot);
          fs.rmdirSync(cacheRoot);
        } catch (_) {
          hadCleanupFailure = true;
        }
      }
      return !hadCleanupFailure;
    } catch (error) {
      Log.e(TAG, `clearCache failed: ${stringifyError(error)}`);
      return false;
    }
  }

  static writeBytesToSavePath(bytes: Uint8Array, destinationUri: string): void {
    try {
      fs.unlinkSync(destinationUri);
    } catch (_) {}
    const destination = fs.openSync(
      destinationUri,
      fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE,
    );
    try {
      const output = FilePickerUtils.toWriteBuffer(bytes);
      FilePickerUtils.writeChunk(destination.fd, output, output.byteLength);
    } finally {
      fs.closeSync(destination);
    }
  }
}
