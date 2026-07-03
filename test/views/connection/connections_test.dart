import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/views/connection/connections.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildOhosConnectionFallback', () {
    final now = DateTime(2026, 6, 19, 15, 0);

    TrackerInfo buildTracker({
      required String id,
      required DateTime start,
      String host = 'example.com',
    }) {
      return TrackerInfo(
        id: id,
        start: start,
        metadata: Metadata(
          network: 'tcp',
          host: host,
          destinationIP: '1.1.1.1',
          destinationPort: '443',
        ),
        chains: const ['test'],
        rule: 'MATCH',
        rulePayload: '',
      );
    }

    test('prefers requests within the recent window', () {
      final stale = buildTracker(
        id: 'stale',
        start: now.subtract(const Duration(minutes: 18)),
      );
      final fresh = buildTracker(
        id: 'fresh',
        start: now.subtract(const Duration(seconds: 5)),
      );

      final result = buildOhosConnectionFallback([stale, fresh], now: now);

      expect(result.map((item) => item.id).toList(), ['fresh']);
    });

    test(
      'falls back to latest unique requests when no recent request exists',
      () {
        final oldest = buildTracker(
          id: 'oldest',
          start: now.subtract(const Duration(minutes: 20)),
        );
        final duplicateOldest = buildTracker(
          id: 'oldest',
          start: now.subtract(const Duration(minutes: 19)),
        );
        final latest = buildTracker(
          id: 'latest',
          start: now.subtract(const Duration(minutes: 18)),
        );

        final result = buildOhosConnectionFallback([
          oldest,
          duplicateOldest,
          latest,
        ], now: now);

        expect(result.map((item) => item.id).toList(), ['latest', 'oldest']);
      },
    );
  });
}
