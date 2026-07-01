import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
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
      picked = await pickerFile(
        withData: true,
        allowedExtensions: const <String>['png', 'jpg', 'jpeg', 'webp'],
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
      }
    } else {
      final xFile = await ImagePicker().pickImage(source: ImageSource.gallery);
      imagePath = xFile?.path;
    }
    if (imagePath == null || imagePath.isEmpty) {
      return null;
    }
    String? result;
    if (system.isOhos) {
      result = await CoreController().decodeQrImage(imagePath);
    } else {
      final controller = MobileScannerController();
      final capture = await controller.analyzeImage(
        imagePath,
        formats: [BarcodeFormat.qrCode],
      );
      result = capture?.barcodes.first.rawValue;
    }
    if (result == null || !result.isUrl) {
      throw currentAppLocalizations.pleaseUploadValidQrcode;
    }
    return result;
  }
}

final picker = Picker();
