import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sanitizeSelectedMap', () {
    test('drops subscription meta values without groups context', () {
      final sanitized = sanitizeSelectedMap(
        groups: const [],
        selectedMap: const {
          'GLOBAL': '剩余流量：2.93 TB',
          '故障转移': '套餐到期：2028-02-04',
          '节点选择': '🇺🇸美国洛杉矶1号',
        },
      );

      expect(sanitized, {'节点选择': '🇺🇸美国洛杉矶1号'});
    });

    test('drops values not present in group candidates', () {
      final sanitized = sanitizeSelectedMap(
        groups: const [
          Group(
            type: GroupType.Selector,
            name: 'GLOBAL',
            all: [
              Proxy(name: '🇺🇸美国洛杉矶1号', type: 'ss'),
              Proxy(name: 'DIRECT', type: 'Direct'),
            ],
          ),
        ],
        selectedMap: const {
          'GLOBAL': '剩余流量：2.93 TB',
        },
      );

      expect(sanitized, isEmpty);
    });
  });

  group('isInvalidSelectedProxyName', () {
    test('recognizes subscription meta labels', () {
      expect(isInvalidSelectedProxyName('剩余流量：2.93 TB'), isTrue);
      expect(isInvalidSelectedProxyName('套餐到期：2028-02-04'), isTrue);
      expect(isInvalidSelectedProxyName('🇯🇵日本三网优化01'), isFalse);
    });
  });

  group('inferGlobalSelection', () {
    test('prefers first non-global selected group', () {
      final inferred = inferGlobalSelection(
        selectedMap: const {
          '节点选择': '🇺🇸美国洛杉矶1号',
          '自动选择': '🇯🇵日本三网优化01',
        },
        groupNames: const ['节点选择', '自动选择', '故障转移'],
      );

      expect(inferred, '节点选择');
    });

    test('falls back to first configured group when selected map is empty', () {
      final inferred = inferGlobalSelection(
        selectedMap: const {},
        groupNames: const ['节点选择', '自动选择'],
      );

      expect(inferred, '节点选择');
    });
  });
}
