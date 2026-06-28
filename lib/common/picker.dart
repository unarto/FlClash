import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

bool isPickerCancellation(Object error) {
  return error is PlatformException &&
      error.code == 'cancelled' &&
      error.message == 'No file selected';
}

class Picker {
  static const _ohosFilePickerChannel = MethodChannel(
    'miguelruivo.flutter.plugins.filepicker',
  );

  List<String>? _allowedExtensionsForSaveFileName(String fileName) {
    final separatorIndex = fileName.lastIndexOf('.');
    if (separatorIndex <= 0 || separatorIndex >= fileName.length - 1) {
      return null;
    }
    final extension = fileName.substring(separatorIndex + 1).trim();
    if (extension.isEmpty) {
      return null;
    }
    return [extension];
  }

  Future<PlatformFile?> pickerFile({
    bool withData = true,
    List<String> allowedExtensions = const <String>[],
  }) async {
    if (system.isOhos) {
      List<dynamic>? picked;
      try {
        picked = await _ohosFilePickerChannel
            .invokeListMethod<dynamic>('pickForFlClash', {
              'allowMultipleSelection': false,
              'allowedExtensions': allowedExtensions,
              'initialDirectory': await appPath.downloadDirPath,
            });
      } on PlatformException catch (error) {
        if (isPickerCancellation(error)) {
          commonPrint.log('[picker] ohos picker cancelled by user');
          return null;
        }
        rethrow;
      }
      if (picked == null || picked.isEmpty) {
        return null;
      }
      final pickedFile = Map<String, dynamic>.from(picked.first as Map);
      final identifier = pickedFile['identifier'] as String?;
      if (identifier == null || identifier.isEmpty) {
        return null;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final resolved = await _ohosFilePickerChannel
          .invokeMapMethod<String, dynamic>('readForFlClash', {
            'uri': identifier,
            'withData': withData,
          });
      if (resolved == null) {
        return null;
      }
      return PlatformFile.fromMap(resolved);
    }
    FilePickerResult? filePickerResult;
    try {
      filePickerResult = await FilePicker.pickFiles(
        withData: withData,
        allowMultiple: false,
        initialDirectory: await appPath.downloadDirPath,
      );
    } on PlatformException catch (error) {
      if (isPickerCancellation(error)) {
        commonPrint.log('[picker] file picker cancelled by user');
        return null;
      }
      rethrow;
    }
    return filePickerResult?.files.first;
  }

  Future<String?> saveFile(String fileName, Uint8List bytes) async {
    final allowedExtensions = _allowedExtensionsForSaveFileName(fileName);
    final path = await FilePicker.saveFile(
      fileName: fileName,
      initialDirectory: await appPath.downloadDirPath,
      allowedExtensions: allowedExtensions,
      bytes: bytes,
    );
    if (!system.isAndroid && !system.isOhos && path != null) {
      final file = File(path);
      await file.safeWriteAsBytes(bytes);
    }
    return path;
  }

  Future<String?> saveFileWithPath(String fileName, String localPath) async {
    final localFile = File(localPath);
    if (!await localFile.exists()) {
      await localFile.create(recursive: true);
    }
    final bytes = (Platform.isAndroid || system.isOhos)
        ? await localFile.readAsBytes()
        : null;
    final allowedExtensions = _allowedExtensionsForSaveFileName(fileName);
    final path = await FilePicker.saveFile(
      fileName: fileName,
      initialDirectory: await appPath.downloadDirPath,
      allowedExtensions: allowedExtensions,
      bytes: bytes,
    );
    if (system.isOhos && path != null) {
      try {
        final resolved = await _ohosFilePickerChannel
            .invokeMapMethod<String, dynamic>('readForFlClash', {
              'uri': path,
              'withData': true,
            });
        final savedBytes = resolved == null
            ? null
            : PlatformFile.fromMap(resolved).bytes;
        if (savedBytes != null) {
          final archive = ZipDecoder().decodeBytes(savedBytes);
          final entries = archive.files
              .map((item) => '${item.name}:${item.isFile ? 'file' : 'dir'}')
              .join(', ');
          commonPrint.log(
            '[zip-verify] saved archive entries=${archive.files.length} [$entries] uri=$path',
          );
        }
      } catch (error) {
        commonPrint.log('[zip-verify] saved archive inspect failed: $error');
      }
    }
    if (path != null && bytes == null) {
      await localFile.copy(path);
    }
    await localFile.safeDelete();
    return path;
  }

  Future<String?> pickerConfigQRCode() async {
    String? imagePath;
    PlatformFile? picked;
    if (system.isOhos) {
      commonPrint.log('[ohos-qr] pickerConfigQRCode use file picker');
      try {
        picked = await pickerFile(
          withData: true,
          allowedExtensions: const <String>['png', 'jpg', 'jpeg', 'webp'],
        );
      } catch (error) {
        final filePickerState = await app?.getLastFilePickerState();
        commonPrint.log(
          '[ohos-qr] pickerConfigQRCode picker error=$error state=$filePickerState',
          logLevel: LogLevel.error,
        );
        rethrow;
      }
      final filePickerState = await app?.getLastFilePickerState();
      commonPrint.log(
        '[ohos-qr] pickerConfigQRCode pickerState=$filePickerState',
      );
      commonPrint.log(
        '[ohos-qr] pickerConfigQRCode picked='
        '${picked == null ? 'null' : '${picked.name} path=${picked.path} bytes=${picked.bytes?.length}'}',
      );
      if (picked == null) {
        return null;
      }
      imagePath = picked.path;
      if ((imagePath == null || imagePath.isEmpty) && picked.bytes != null) {
        final tempPath = await appPath.tempFilePath;
        final suffix = picked.extension?.trim();
        final normalizedPath = suffix == null || suffix.isEmpty
            ? '$tempPath.png'
            : '$tempPath.$suffix';
        await File(normalizedPath).safeWriteAsBytes(picked.bytes!);
        imagePath = normalizedPath;
        commonPrint.log(
          '[ohos-qr] pickerConfigQRCode wrote temp image path=$imagePath',
        );
      }
    } else {
      final xFile = await ImagePicker().pickImage(source: ImageSource.gallery);
      imagePath = xFile?.path;
    }
    commonPrint.log('[ohos-qr] pickerConfigQRCode imagePath=$imagePath');
    if (imagePath == null || imagePath.isEmpty) {
      return null;
    }
    String? result;
    if (system.isOhos) {
      result = await CoreController().decodeQrImage(imagePath);
      commonPrint.log(
        '[ohos-qr] pickerConfigQRCode capture=${result.isEmpty ? 0 : 1}',
      );
    } else {
      final controller = MobileScannerController();
      final capture = await controller.analyzeImage(
        imagePath,
        formats: [BarcodeFormat.qrCode],
      );
      commonPrint.log(
        '[ohos-qr] pickerConfigQRCode capture=${capture?.barcodes.length}',
      );
      result = capture?.barcodes.first.rawValue;
    }
    commonPrint.log('[ohos-qr] pickerConfigQRCode rawResult=$result');
    if (result == null || !result.isUrl) {
      throw currentAppLocalizations.pleaseUploadValidQrcode;
    }
    return result;
  }
}

final picker = Picker();
