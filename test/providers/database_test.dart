import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/profile.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('withRollback', () {
    test('rolls back with snapshot and rethrows async errors', () async {
      final error = StateError('write failed');
      final previous = [1, 2, 3];
      List<int>? rolledBack;

      await expectLater(
        withRollback(
          snapshot: previous,
          action: () async {
            throw error;
          },
          rollback: (value) => rolledBack = value,
        ),
        throwsA(same(error)),
      );

      expect(rolledBack, previous);
    });

    test('does not roll back when action succeeds', () async {
      var rollbackCalled = false;

      await withRollback(
        snapshot: [1, 2, 3],
        action: () async {},
        rollback: (_) => rollbackCalled = true,
      );

      expect(rollbackCalled, false);
    });
  });

  group('profile insertion order', () {
    test('copyAndPut inserts a new profile at the front', () {
      final existing = [
        Profile.normal(label: 'old-a').copyWith(id: 1, order: 0),
        Profile.normal(label: 'old-b').copyWith(id: 2, order: 1),
      ];
      final inserted = Profile.normal().copyWith(id: 3, label: '', order: null);

      final next = existing.copyAndPut(inserted, (item) => item.id == inserted.id);

      expect(next.map((item) => item.id), [3, 1, 2]);
      expect(next.first.realLabel, '3');
    });
  });
}
