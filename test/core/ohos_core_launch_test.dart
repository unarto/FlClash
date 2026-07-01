import 'package:fl_clash/core/ohos_core_launch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OhosCoreLaunch', () {
    test('child launch tracks killable external pid', () {
      const launch = OhosCoreLaunch.child(pid: 1234);

      expect(launch.mode, OhosCoreLaunchMode.child);
      expect(launch.pid, 1234);
      expect(launch.hasTrackedCore, isTrue);
      expect(launch.canStopExternally, isTrue);
    });

    test('bundled launch tracks killable external pid', () {
      const launch = OhosCoreLaunch.bundled(pid: 5678);

      expect(launch.mode, OhosCoreLaunchMode.bundled);
      expect(launch.pid, 5678);
      expect(launch.hasTrackedCore, isTrue);
      expect(launch.canStopExternally, isTrue);
    });

    test('embedded launch is tracked without exposing fake external pid', () {
      const launch = OhosCoreLaunch.embedded();

      expect(launch.mode, OhosCoreLaunchMode.embedded);
      expect(launch.pid, isNull);
      expect(launch.hasTrackedCore, isTrue);
      expect(launch.canStopExternally, isFalse);
    });

    test('none launch reports no tracked core', () {
      const launch = OhosCoreLaunch.none();

      expect(launch.mode, OhosCoreLaunchMode.none);
      expect(launch.pid, isNull);
      expect(launch.hasTrackedCore, isFalse);
      expect(launch.canStopExternally, isFalse);
    });

    test('preserves tracked launch when native stop fails', () {
      const launch = OhosCoreLaunch.child(pid: 1234);

      expect(
        resolveOhosCoreLaunchAfterStopAttempt(launch, stopped: false),
        launch,
      );
    });

    test('clears tracked launch when native stop succeeds', () {
      const launch = OhosCoreLaunch.bundled(pid: 5678);

      expect(
        resolveOhosCoreLaunchAfterStopAttempt(launch, stopped: true),
        const OhosCoreLaunch.none(),
      );
    });
  });
}
