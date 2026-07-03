import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fl_clash/core/service.dart';
import 'package:fl_clash/core/transport.dart';
import 'package:fl_clash/core/event.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/core.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCoreTransport extends IPCCoreTransport {
  FakeCoreTransport({bool initiallyConnected = true})
    : connectionCompleterOverride = Completer<void>(),
      readyCompleterOverride = Completer<void>()..complete(),
      super(address: '/tmp/fake-core-transport') {
    if (initiallyConnected) {
      connectionCompleterOverride.complete();
    }
  }

  final Completer<void> connectionCompleterOverride;
  final Completer<void> readyCompleterOverride;
  final StreamController<Uint8List> dataController =
      StreamController<Uint8List>.broadcast();
  final List<String> sentMessages = [];

  @override
  Completer<void> get connectionCompleter => connectionCompleterOverride;

  @override
  Completer<void> get readyCompleter => readyCompleterOverride;

  @override
  Stream<Uint8List> get dataStream => dataController.stream;

  @override
  Future<void> init() async {}

  @override
  void send(String message) {
    sentMessages.add(message);
  }

  @override
  Future<void> disconnect() async {
    onDisconnect?.call();
  }

  @override
  Future<void> close() async {
    await dataController.close();
  }

  void triggerDisconnect() {
    onDisconnect?.call();
  }

  void connect() {
    if (!connectionCompleterOverride.isCompleted) {
      connectionCompleterOverride.complete();
    }
  }
}

class FakeProcess implements Process {
  FakeProcess();

  bool killed = false;

  @override
  Future<int> get exitCode async => 0;

  @override
  int get pid => 42;

  @override
  IOSink get stdin => throw UnimplementedError();

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    return true;
  }
}

void main() {
  group('CoreService', () {
    test('disconnect completes pending invoke with null immediately', () async {
      final transport = FakeCoreTransport();
      final service = CoreService.test(transport);

      await Future<void>.delayed(Duration.zero);

      final future = service.invoke<bool>(method: ActionMethod.getIsInit);
      await Future<void>.delayed(Duration.zero);

      expect(transport.sentMessages, hasLength(1));

      transport.triggerDisconnect();

      await expectLater(
        future.timeout(const Duration(milliseconds: 100)),
        completion(isNull),
      );
    });

    test('dispatches core events even when the incoming result omits id', () async {
      final transport = FakeCoreTransport();
      final service = CoreService.test(transport);
      final crashes = <String>[];
      final listener = _CrashListener(crashes);
      coreEventManager.addListener(listener);
      addTearDown(() {
        coreEventManager.removeListener(listener);
      });

      await Future<void>.delayed(Duration.zero);

      await service.handleResult(
        const ActionResult(
          method: ActionMethod.message,
          data: {'type': 'crash', 'data': 'missing id event'},
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(crashes, ['missing id event']);
    });

    test('timed out invoke is not sent after a later connection', () async {
      final transport = FakeCoreTransport(initiallyConnected: false);
      final service = CoreService.test(transport);

      await Future<void>.delayed(Duration.zero);

      final future = service.invoke<bool>(
        method: ActionMethod.getIsInit,
        timeout: const Duration(milliseconds: 10),
      );

      await expectLater(future, completion(isNull));
      expect(transport.sentMessages, isEmpty);

      transport.connect();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(transport.sentMessages, isEmpty);
    });

    test('user shutdown returns immediately when transport was never connected', () async {
      final transport = FakeCoreTransport(initiallyConnected: false);
      final service = CoreService.test(transport);

      await Future<void>.delayed(Duration.zero);

      await expectLater(
        service.shutdown(true).timeout(const Duration(milliseconds: 100)),
        completion(isTrue),
      );
    });

    test('non-user shutdown while disconnected does not suppress a later real crash', () async {
      final transport = FakeCoreTransport(initiallyConnected: false);
      final service = CoreService.test(transport);
      final crashes = <String>[];
      final listener = _CrashListener(crashes);
      coreEventManager.addListener(listener);
      addTearDown(() {
        coreEventManager.removeListener(listener);
      });

      await Future<void>.delayed(Duration.zero);

      await expectLater(service.shutdown(false), completion(isTrue));
      transport.connect();
      transport.triggerDisconnect();
      await Future<void>.delayed(Duration.zero);

      expect(crashes, ['core done']);
    });

    test('non-user shutdown suppresses the later expected disconnect crash', () async {
      final transport = FakeCoreTransport();
      final service = CoreService.test(transport);
      final crashes = <String>[];
      final listener = _CrashListener(crashes);
      coreEventManager.addListener(listener);
      addTearDown(() {
        coreEventManager.removeListener(listener);
      });

      await Future<void>.delayed(Duration.zero);

      await expectLater(service.shutdown(false), completion(isTrue));
      transport.triggerDisconnect();
      await Future<void>.delayed(Duration.zero);

      expect(crashes, isEmpty);
    });

    test('start kills desktop process when connection times out', () async {
      final transport = FakeCoreTransport(initiallyConnected: false);
      final process = FakeProcess();
      final service = CoreService.test(
        transport,
        connectionTimeout: const Duration(milliseconds: 10),
        startDesktopProcess: (_, _) async => process,
        coreExecutablePath: () => '/tmp/fake-core',
      );

      await Future<void>.delayed(Duration.zero);

      await expectLater(service.preload(), completion('core connection timeout'));
      expect(process.killed, isTrue);
    });
  });
}

class _CrashListener with CoreEventListener {
  _CrashListener(this.crashes);

  final List<String> crashes;

  @override
  void onCrash(String message) {
    crashes.add(message);
  }
}
