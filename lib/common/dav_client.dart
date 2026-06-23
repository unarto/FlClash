import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:webdav_client/webdav_client.dart';

class DAVClient {
  late Client client;
  late String fileName;
  bool _rootReady = false;

  DAVClient(DAVProps dav) {
    client = newClient(dav.uri, user: dav.user, password: dav.password);
    fileName = dav.fileName;
    client.setHeaders({'accept-charset': 'utf-8', 'Content-Type': 'text/xml'});
    client.setConnectTimeout(8000);
    client.setSendTimeout(60000);
    client.setReceiveTimeout(60000);
  }

  Future<bool> ping() async {
    try {
      commonPrint.log('[dav-client] ping start root=$root backupFile=$backupFile');
      await client.ping();
      commonPrint.log('[dav-client] ping success root=$root');
      return true;
    } catch (error) {
      commonPrint.log('[dav-client] ping failed root=$root error=$error');
      return false;
    }
  }

  String get root => '/$appName';

  String get backupFile => '$root/$fileName';

  Future<void> _ensureRoot() async {
    if (_rootReady) return;
    try {
      await client.readDir(root);
      _rootReady = true;
      return;
    } catch (_) {}
    await client.mkdirAll(root);
    _rootReady = true;
  }

  Future<bool> backup(String localFilePath) async {
    commonPrint.log(
      '[dav-client] backup start local=$localFilePath remote=$backupFile',
    );
    await _ensureRoot();
    await client.writeFromFile(localFilePath, backupFile);
    commonPrint.log('[dav-client] backup success remote=$backupFile');
    return true;
  }

  Future<bool> restore() async {
    commonPrint.log('[dav-client] restore start remote=$backupFile');
    await _ensureRoot();
    final backupFilePath = await appPath.backupFilePath;
    await client.read2File(backupFile, backupFilePath);
    commonPrint.log(
      '[dav-client] restore success remote=$backupFile local=$backupFilePath',
    );
    return true;
  }
}
