import 'dart:async';
import 'dart:io';

import 'package:fl_clash/pages/error.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_api/rust_api.dart';

import 'application.dart';
import 'common/common.dart';

Future<void> main() async {
  try {
    print('[BOOT] main enter');
    WidgetsFlutterBinding.ensureInitialized();
    print('[BOOT] binding ready');
    if (system.isDesktop) {
      await RustLib.init();
    }
    print('[BOOT] rust init skipped-or-done');
    await CoreController.initOhosCoreBinary();
    print('[BOOT] ohos core binary init skipped-or-done');
    final version = await system.version;
    print('[BOOT] version=$version');
    final container = await globalState.init(version);
    print('[BOOT] globalState init done');
    HttpOverrides.global = FlClashHttpOverrides();
    print('[BOOT] running app');
    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const Application(),
      ),
    );
  } catch (e, s) {
    print('[BOOT] main catch: $e');
    print(s);
    return runApp(
      MaterialApp(
        home: InitErrorScreen(error: e, stack: s),
      ),
    );
  }
}
