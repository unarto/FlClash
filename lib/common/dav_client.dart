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
      await client.ping();
      return true;
    } catch (_) {
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
    await _ensureRoot();
    await client.writeFromFile(localFilePath, backupFile);
    return true;
  }

  Future<bool> restore() async {
    await _ensureRoot();
    final backupFilePath = await appPath.backupFilePath;
    await client.read2File(backupFile, backupFilePath);
    return true;
  }
}
