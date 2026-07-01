import 'dart:io';
import 'dart:typed_data';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'clash_config.dart';

part 'generated/profile.freezed.dart';
part 'generated/profile.g.dart';

@freezed
abstract class SubscriptionInfo with _$SubscriptionInfo {
  const factory SubscriptionInfo({
    @Default(0) int upload,
    @Default(0) int download,
    @Default(0) int total,
    @Default(0) int expire,
  }) = _SubscriptionInfo;

  factory SubscriptionInfo.fromJson(Map<String, Object?> json) =>
      _$SubscriptionInfoFromJson(json);

  factory SubscriptionInfo.formHString(String? info) {
    if (info == null) return const SubscriptionInfo();
    final list = info.split(';');
    final Map<String, int?> map = {};
    for (final i in list) {
      final keyValue = i.trim().split('=');
      map[keyValue[0]] = int.tryParse(keyValue[1]);
    }
    return SubscriptionInfo(
      upload: map['upload'] ?? 0,
      download: map['download'] ?? 0,
      total: map['total'] ?? 0,
      expire: map['expire'] ?? 0,
    );
  }
}

@freezed
abstract class Profile with _$Profile {
  const factory Profile({
    required int id,
    @Default('') String label,
    String? currentGroupName,
    @Default('') String url,
    DateTime? lastUpdateDate,
    required Duration autoUpdateDuration,
    SubscriptionInfo? subscriptionInfo,
    @Default(true) bool autoUpdate,
    @Default({}) Map<String, String> selectedMap,
    @Default({}) Set<String> unfoldSet,
    @Default(OverwriteType.standard) OverwriteType overwriteType,
    int? scriptId,
    int? order,
  }) = _Profile;

  factory Profile.fromJson(Map<String, Object?> json) =>
      _$ProfileFromJson(json);

  factory Profile.normal({String? label, String url = ''}) {
    final id = snowflake.id;
    return Profile(
      label: label ?? '',
      url: url,
      id: id,
      autoUpdateDuration: defaultUpdateDuration,
    );
  }
}

@freezed
abstract class ProfileRuleLink with _$ProfileRuleLink {
  const factory ProfileRuleLink({
    int? profileId,
    required int ruleId,
    RuleScene? scene,
    String? order,
  }) = _ProfileRuleLink;
}

extension ProfileRuleLinkExt on ProfileRuleLink {
  String get key {
    final splits = <String?>[
      profileId?.toString(),
      ruleId.toString(),
      scene?.name,
    ];
    return splits.where((item) => item != null).join('_');
  }
}

// @freezed
// abstract class Overwrite with _$Overwrite {
//   const factory Overwrite({
//     @Default(OverwriteType.standard) OverwriteType type,
//     @Default(StandardOverwrite()) StandardOverwrite standardOverwrite,
//     @Default(ScriptOverwrite()) ScriptOverwrite scriptOverwrite,
//   }) = _Overwrite;
//
//   factory Overwrite.fromJson(Map<String, Object?> json) =>
//       _$OverwriteFromJson(json);
// }

@freezed
abstract class StandardOverwrite with _$StandardOverwrite {
  const factory StandardOverwrite({
    @Default([]) List<Rule> addedRules,
    @Default([]) List<int> disabledRuleIds,
  }) = _StandardOverwrite;

  factory StandardOverwrite.fromJson(Map<String, Object?> json) =>
      _$StandardOverwriteFromJson(json);
}

@freezed
abstract class ScriptOverwrite with _$ScriptOverwrite {
  const factory ScriptOverwrite({int? scriptId}) = _ScriptOverwrite;

  factory ScriptOverwrite.fromJson(Map<String, Object?> json) =>
      _$ScriptOverwriteFromJson(json);
}

extension ProfilesExt on List<Profile> {
  Profile? getProfile(int? profileId) {
    final index = indexWhere((profile) => profile.id == profileId);
    return index == -1 ? null : this[index];
  }

  String _getLabel(String label, int id) {
    final realLabel = label.takeFirstValid([id.toString()]);
    final hasDup =
        indexWhere(
          (element) => element.label == realLabel && element.id != id,
        ) !=
        -1;
    if (hasDup) {
      return _getLabel(utils.getOverwriteLabel(realLabel), id);
    } else {
      return label;
    }
  }

  Profile optimizeLabel(Profile profile) {
    return profile.copyWith(label: _getLabel(profile.label, profile.id));
  }
}

extension ProfileExtension on Profile {
  static String _expandIndentedBlock(String indent, String block) {
    return block.split('\n').map((line) => '$indent$line').join('\n');
  }

  static int _leadingWhitespaceCount(String line) {
    var count = 0;
    while (count < line.length) {
      final char = line.codeUnitAt(count);
      if (char != 0x20 && char != 0x09) {
        break;
      }
      count++;
    }
    return count;
  }

  static bool _isUnsetCertificateValue(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == '""' || normalized == "''") {
      return true;
    }
    if (normalized.startsWith('#')) {
      return true;
    }
    return false;
  }

  static bool _isEmptyBlockScalarIndicator(String value) {
    final normalized = value.trim();
    return RegExp(r'^[|>][-+]?\s*(?:#.*)?$').hasMatch(normalized);
  }

  static String _removeUnsetCertificateFields(String text) {
    final lines = text.split('\n');
    final output = <String>[];
    var index = 0;
    while (index < lines.length) {
      final line = lines[index];
      final match = RegExp(
        r'^([ \t]*)(certificate|private-key)\s*:\s*(.*)$',
      ).firstMatch(line);
      if (match == null) {
        output.add(line);
        index++;
        continue;
      }
      final indent = match.group(1) ?? '';
      final value = match.group(3) ?? '';
      if (_isUnsetCertificateValue(value)) {
        index++;
        continue;
      }
      if (_isEmptyBlockScalarIndicator(value)) {
        final baseIndent = indent.length;
        final blockLines = <String>[];
        var cursor = index + 1;
        while (cursor < lines.length) {
          final nextLine = lines[cursor];
          if (nextLine.trim().isEmpty) {
            blockLines.add(nextLine);
            cursor++;
            continue;
          }
          final nextIndent = _leadingWhitespaceCount(nextLine);
          if (nextIndent <= baseIndent) {
            break;
          }
          blockLines.add(nextLine);
          cursor++;
        }
        final hasRealContent = blockLines.any((blockLine) {
          final trimmed = blockLine.trim();
          return trimmed.isNotEmpty && !trimmed.startsWith('#');
        });
        if (!hasRealContent) {
          index = cursor;
          continue;
        }
      }
      output.add(line);
      index++;
    }
    return output.join('\n');
  }

  static String _collapseSingletonScalarBlocks(String text, Set<String> keys) {
    final lines = text.split('\n');
    final output = <String>[];
    var index = 0;
    while (index < lines.length) {
      final line = lines[index];
      final match = RegExp(r'^([ \t]*)([^:#]+)\s*:\s*$').firstMatch(line);
      if (match == null) {
        output.add(line);
        index++;
        continue;
      }
      final indent = match.group(1) ?? '';
      final key = (match.group(2) ?? '').trim();
      if (!keys.contains(key)) {
        output.add(line);
        index++;
        continue;
      }
      final baseIndent = indent.length;
      final blockLines = <String>[];
      var cursor = index + 1;
      while (cursor < lines.length) {
        final nextLine = lines[cursor];
        if (nextLine.trim().isEmpty) {
          blockLines.add(nextLine);
          cursor++;
          continue;
        }
        final nextIndent = _leadingWhitespaceCount(nextLine);
        if (nextIndent <= baseIndent) {
          break;
        }
        blockLines.add(nextLine);
        cursor++;
      }
      final contentLines = blockLines.where((blockLine) {
        final trimmed = blockLine.trim();
        return trimmed.isNotEmpty && !trimmed.startsWith('#');
      }).toList();
      if (contentLines.length != 1) {
        output.add(line);
        index++;
        continue;
      }
      final contentLine = contentLines.first;
      final trimmedContent = contentLine.trim();
      final scalarValue = trimmedContent.split(RegExp(r'\s+#')).first.trim();
      if (scalarValue.startsWith('- ') || scalarValue.contains(': ')) {
        output.add(line);
        index++;
        continue;
      }
      output.add('$indent$key: $trimmedContent');
      index = cursor;
    }
    return output.join('\n');
  }

  static String _ensureListenerCertificatePlaceholders(
    String text,
    Set<String> listenerNames,
  ) {
    final lines = text.split('\n');
    final output = <String>[];
    var index = 0;
    var inListenersSection = false;

    bool isTopLevelSection(String line) {
      if (line.trim().isEmpty || line.trimLeft().startsWith('#')) {
        return false;
      }
      return RegExp(r'^[^ \t][^:]*:\s*(?:#.*)?$').hasMatch(line);
    }

    while (index < lines.length) {
      final line = lines[index];
      if (!inListenersSection) {
        output.add(line);
        if (line.trim() == 'listeners:') {
          inListenersSection = true;
        }
        index++;
        continue;
      }

      if (isTopLevelSection(line) && line.trim() != 'listeners:') {
        inListenersSection = false;
        output.add(line);
        index++;
        continue;
      }

      final itemMatch = RegExp(
        r'^([ \t]*)-\s+name:\s*(.+?)\s*(?:#.*)?$',
      ).firstMatch(line);
      if (itemMatch == null) {
        output.add(line);
        index++;
        continue;
      }

      final itemIndent = itemMatch.group(1) ?? '';
      final nameToken = (itemMatch.group(2) ?? '').trim();
      final listenerName = nameToken.replaceAll(RegExp(r'''^["']|["']$'''), '');
      final block = <String>[line];
      var cursor = index + 1;
      while (cursor < lines.length) {
        final nextLine = lines[cursor];
        if (RegExp(
              '^${RegExp.escape(itemIndent)}-\\s+name:',
            ).hasMatch(nextLine) ||
            isTopLevelSection(nextLine)) {
          break;
        }
        block.add(nextLine);
        cursor++;
      }

      if (!listenerNames.contains(listenerName)) {
        output.addAll(block);
        index = cursor;
        continue;
      }

      var hasCertificate = false;
      var hasPrivateKey = false;
      for (final blockLine in block) {
        if (RegExp(r'^[ \t]+certificate\s*:').hasMatch(blockLine)) {
          hasCertificate = true;
        } else if (RegExp(r'^[ \t]+private-key\s*:').hasMatch(blockLine)) {
          hasPrivateKey = true;
        }
      }

      if (hasCertificate && hasPrivateKey) {
        output.addAll(block);
        index = cursor;
        continue;
      }

      var insertAt = -1;
      for (var i = 0; i < block.length; i++) {
        if (RegExp(r'^[ \t]+listen\s*:').hasMatch(block[i])) {
          insertAt = i + 1;
          break;
        }
      }
      if (insertAt == -1) {
        for (var i = 0; i < block.length; i++) {
          if (RegExp(r'^[ \t]+port\s*:').hasMatch(block[i])) {
            insertAt = i + 1;
            break;
          }
        }
      }
      if (insertAt == -1) {
        insertAt = block.length;
      }

      final childIndent = '$itemIndent  ';
      final additions = <String>[
        if (!hasCertificate) '${childIndent}certificate: ./server.crt',
        if (!hasPrivateKey) '${childIndent}private-key: ./server.key',
      ];
      output.addAll(block.take(insertAt));
      output.addAll(additions);
      output.addAll(block.skip(insertAt));
      index = cursor;
    }

    return output.join('\n');
  }

  @visibleForTesting
  static Uint8List normalizeImportedConfigBytes(Uint8List bytes) {
    try {
      final rawText = String.fromCharCodes(bytes);
      var normalized = rawText;
      final hasPlaceholder = RegExp(
        r'(^|\n)\s*external-ui\s*:\s*/path/to/ui/folder/\s*(\n|$)',
        multiLine: true,
      );
      if (hasPlaceholder.hasMatch(normalized)) {
        normalized = normalized.replaceAllMapped(
          hasPlaceholder,
          (match) =>
              '${match.group(1) ?? ''}external-ui: ""${match.group(2) ?? ''}',
        );
      }
      normalized = normalized.replaceAll(
        'path: /test.yaml',
        'path: ./test.yaml',
      );
      normalized = normalized.replaceAll(
        'path: /path/to/save/file.yaml',
        'path: ./path/to/save/file.yaml',
      );
      normalized = normalized.replaceAll(
        'path: /path/to/save/file.mrs',
        'path: ./path/to/save/file.mrs',
      );
      normalized = normalized.replaceAll('IP-ASN,1,PROXY', 'IP-ASN,1,DIRECT');
      normalized = normalized.replaceAll('\n    - rule-set:fakeip-filter', '');
      normalized = normalized.replaceAll('\n    - geosite:fakeip-filter', '');
      normalized = normalized.replaceAll('''tunnels: # one line config
  - tcp/udp,127.0.0.1:6553,114.114.114.114:53,proxy
  - tcp,127.0.0.1:6666,rds.mysql.com:3306,vpn
  # full yaml config
  - network: [tcp, udp]
    address: 127.0.0.1:7777
    target: target.com
    proxy: proxy

''', '');
      normalized = normalized.replaceAll('\n    dialer-proxy: proxy', '');
      final hasAbsoluteExternalUi = RegExp(
        r'(^|\n)(\s*external-ui\s*:\s*)(/(?!/)[^\n#]*)(\s*(?:#.*)?)(?=\n|$)',
        multiLine: true,
      );
      if (hasAbsoluteExternalUi.hasMatch(normalized)) {
        normalized = normalized.replaceAllMapped(
          hasAbsoluteExternalUi,
          (match) =>
              '${match.group(1) ?? ''}${match.group(2) ?? ''}""${match.group(4) ?? ''}',
        );
      }
      normalized = normalized.replaceAll('- vmess1', '- vmess');
      final hasDeprecatedRelayGroup = RegExp(
        r'(^|\n)\s*-\s*name\s*:\s*"relay"\s*\n'
        r'\s*type\s*:\s*relay\s*\n'
        r'(?:\s+.*\n)*?(?=(?:\s*-\s*name\s*:)|(?:\S)|\Z)',
        multiLine: true,
      );
      final hadRelayGroup = hasDeprecatedRelayGroup.hasMatch(normalized);
      if (hadRelayGroup) {
        try {
          commonPrint.log('[profile-normalize] relay group match detected');
        } catch (_) {}
      }
      if (hasDeprecatedRelayGroup.hasMatch(normalized)) {
        normalized = normalized.replaceAllMapped(hasDeprecatedRelayGroup, (
          match,
        ) {
          final prefix = match.group(1) ?? '';
          return prefix == '\n' ? '\n' : '';
        });
      }
      if (hadRelayGroup) {
        try {
          final relayStillPresent = RegExp(
            r'(^|\n)\s*-\s*name\s*:\s*"relay"\s*\n\s*type\s*:\s*relay\b',
            multiLine: true,
          ).hasMatch(normalized);
          commonPrint.log(
            '[profile-normalize] relay group removed=${!relayStillPresent}',
          );
        } catch (_) {}
      }
      final hasSingletonProxyList = RegExp(
        r'(^|\n)(\s*(?:server|password)\s*:\s*)\[\s*([^\]\n#]+?)\s*\](\s*(?:#.*)?)',
        multiLine: true,
      );
      if (hasSingletonProxyList.hasMatch(normalized)) {
        normalized = normalized.replaceAllMapped(
          hasSingletonProxyList,
          (match) =>
              '${match.group(1) ?? ''}${match.group(2) ?? ''}${match.group(3) ?? ''}${match.group(4) ?? ''}',
        );
      }
      final hasSingletonProxyBlockList = RegExp(
        r'(^|\n)(\s*)(server|password)\s*:\s*\n\2\s*-\s*([^\n]+?)\s*(?=\n|$)',
        multiLine: true,
      );
      if (hasSingletonProxyBlockList.hasMatch(normalized)) {
        normalized = normalized.replaceAllMapped(
          hasSingletonProxyBlockList,
          (match) =>
              '${match.group(1) ?? ''}${match.group(2) ?? ''}${match.group(3) ?? ''}: ${match.group(4) ?? ''}',
        );
      }
      normalized = _collapseSingletonScalarBlocks(normalized, {
        'server',
        'password',
        'host',
        'client-fingerprint',
      });
      const vlessEncryptionPlaceholder =
          'mlkem768x25519plus.native/xorpub/random.1rtt/0rtt.(padding len).(padding gap).(X25519 Password).(ML-KEM-768 Client)...';
      const openVpnCertPlaceholder = 'MIIB...example';
      const openVpnKeyPlaceholder = 'MIIE...example';
      const openVpnTlsCryptPlaceholder = '...';
      const openVpnCertSample = '''
MIIBszCCAVmgAwIBAgIUQbG/Z7JQGg+Jb42bBYK6q8I4g5swCgYIKoZIzj0EAwIw
EjEQMA4GA1UEAwwHbWlob21vMB4XDTI2MDUwMTAwMDAwMFoXDTM2MDQyOTAwMDAw
MFowEjEQMA4GA1UEAwwHbWlob21vMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE
hT8O8v9COiL0e7Gmab6r8jYxgB5xIvEtL10eF6QpJm+5ROK8f8yO8JHj2L2F6i1v
g7CNgMCoX9YnZ9wqOqNTMFEwHQYDVR0OBBYEFDuK1nBI7w+Kz8o9hD7UzpJkq1N2
MB8GA1UdIwQYMBaAFDuK1nBI7w+Kz8o9hD7UzpJkq1N2MA8GA1UdEwEB/wQFMAMB
Af8wCgYIKoZIzj0EAwIDSAAwRQIhAJ4mquCRw+W1M7RCNzUVpV9qPzR9qYpK4SAi
6pEh8FeaAiBKv+YbWBjjiWk0Yxch3v7y8W7S7e3pVtHh8x9n9+6w1Q==''';
      const openVpnKeySample = '''
MHcCAQEEIG1paG9tb19vcGVudnBuX3Rlc3Rfa2V5XzEyMzQ1Njc4oAoGCCqGSM49
AwEHoUQDQgAEhT8O8v9COiL0e7Gmab6r8jYxgB5xIvEtL10eF6QpJm+5ROK8f8yO
8JHj2L2F6i1vg7CNgMCoX9YnZ9wqOg==''';
      const openVpnTlsCryptBytes = '''
00000000000000000000000000000000
00000000000000000000000000000000
00000000000000000000000000000000
00000000000000000000000000000000
00000000000000000000000000000000
00000000000000000000000000000000
00000000000000000000000000000000
00000000000000000000000000000000
00000000000000000000000000000000
00000000000000000000000000000000
00000000000000000000000000000000
00000000000000000000000000000000
00000000000000000000000000000000
00000000000000000000000000000000
00000000000000000000000000000000
00000000000000000000000000000000''';
      String openVpnTlsCryptBody(String indent) =>
          _expandIndentedBlock(indent, openVpnTlsCryptBytes);
      String openVpnTlsCryptSample(String indent) =>
          _expandIndentedBlock(indent, '''
-----BEGIN OpenVPN Static key V1-----
$openVpnTlsCryptBytes
-----END OpenVPN Static key V1-----''');
      if (normalized.contains(vlessEncryptionPlaceholder)) {
        normalized = normalized.replaceAll(vlessEncryptionPlaceholder, 'none');
      }
      final hasOpenVpnCertPlaceholder = RegExp(
        '^([ \\t]*)${RegExp.escape(openVpnCertPlaceholder)}\$',
        multiLine: true,
      );
      if (hasOpenVpnCertPlaceholder.hasMatch(normalized)) {
        normalized = normalized.replaceAllMapped(
          hasOpenVpnCertPlaceholder,
          (match) =>
              _expandIndentedBlock(match.group(1) ?? '', openVpnCertSample),
        );
      }
      final hasOpenVpnKeyPlaceholder = RegExp(
        '^([ \\t]*)${RegExp.escape(openVpnKeyPlaceholder)}\$',
        multiLine: true,
      );
      if (hasOpenVpnKeyPlaceholder.hasMatch(normalized)) {
        normalized = normalized.replaceAllMapped(
          hasOpenVpnKeyPlaceholder,
          (match) =>
              _expandIndentedBlock(match.group(1) ?? '', openVpnKeySample),
        );
      }
      final hasOpenVpnTlsCryptBodyPlaceholder = RegExp(
        '(^|\\n)([ \\t]*)-----BEGIN OpenVPN Static key V1-----\\n'
        r'(([ \t]*[0-9a-fA-F]+\n)*)'
        r'([ \t]*)\.\.\.\s*(?=\n)'
        '\\n([ \\t]*)-----END OpenVPN Static key V1-----',
        multiLine: true,
      );
      if (hasOpenVpnTlsCryptBodyPlaceholder.hasMatch(normalized)) {
        normalized = normalized.replaceAllMapped(
          hasOpenVpnTlsCryptBodyPlaceholder,
          (match) =>
              '${match.group(1) ?? ''}'
              '${match.group(2) ?? ''}-----BEGIN OpenVPN Static key V1-----\n'
              '${openVpnTlsCryptBody(match.group(5) ?? '')}\n'
              '${match.group(6) ?? ''}-----END OpenVPN Static key V1-----',
        );
      }
      final hasOpenVpnTlsCryptPlaceholder = RegExp(
        '^([ \\t]*)${RegExp.escape(openVpnTlsCryptPlaceholder)}\$',
        multiLine: true,
      );
      if (hasOpenVpnTlsCryptPlaceholder.hasMatch(normalized)) {
        normalized = normalized.replaceAllMapped(
          hasOpenVpnTlsCryptPlaceholder,
          (match) => openVpnTlsCryptSample(match.group(1) ?? ''),
        );
      }
      final hasInlineCaTags = RegExp(
        r'(^|\n)\s*</?ca>\s*(?=\n|$)',
        multiLine: true,
      );
      if (hasInlineCaTags.hasMatch(normalized)) {
        normalized = normalized.replaceAllMapped(hasInlineCaTags, (match) {
          final prefix = match.group(1);
          return prefix == '\n' ? '\n' : '';
        });
      }
      final hasRealityPublicKeyPlaceholder = RegExp(
        r'(^|\n)(\s*public-key\s*:\s*)xxx(\s*(?=\n|$))',
        multiLine: true,
      );
      if (hasRealityPublicKeyPlaceholder.hasMatch(normalized)) {
        normalized = normalized.replaceAllMapped(
          hasRealityPublicKeyPlaceholder,
          (match) =>
              '${match.group(1) ?? ''}${match.group(2) ?? ''}CrrQSjAG_YkHLwvM2M-7XkKJilgL5upBKCp0od0tLhE${match.group(3) ?? ''}',
        );
      }
      final hasUnsetCertificateFields = RegExp(
        r'''(^|\n)(\s*(?:certificate|private-key)\s*:\s*)(?:""|''|\s*)(\s*(?:#.*)?)(?=\n|$)''',
        multiLine: true,
      );
      if (hasUnsetCertificateFields.hasMatch(normalized)) {
        normalized = normalized.replaceAllMapped(
          hasUnsetCertificateFields,
          (match) => match.group(1) == '\n' ? '\n' : '',
        );
      }
      final hasUnsetCertificatePlaceholderBlock = RegExp(
        r'(^|\n)([ \t]*)(certificate|private-key)\s*:\s*(?:#.*)?\n'
        r'((?:\2[ \t]+(?:#.*)?\n)*)'
        r'(?=(?:\2[^ \t\n#])|(?:[^ \t\n])|\Z)',
        multiLine: true,
      );
      if (hasUnsetCertificatePlaceholderBlock.hasMatch(normalized)) {
        normalized = normalized.replaceAllMapped(
          hasUnsetCertificatePlaceholderBlock,
          (match) => match.group(1) == '\n' ? '\n' : '',
        );
      }
      normalized = _removeUnsetCertificateFields(normalized);
      normalized = _ensureListenerCertificatePlaceholders(normalized, {
        'tuic-in-1',
        'hysteria2-in-1',
      });
      normalized = normalized.replaceAll(
        'short-id: xxx # optional',
        'short-id: 10f897e26c4b9478 # optional',
      );
      normalized = normalized.replaceAll(
        'short-id: xxx',
        'short-id: 10f897e26c4b9478',
      );
      if (normalized == rawText) {
        return bytes;
      }
      return Uint8List.fromList(normalized.codeUnits);
    } catch (_) {
      return bytes;
    }
  }

  ProfileType get type =>
      url.isEmpty == true ? ProfileType.file : ProfileType.url;

  bool get realAutoUpdate => url.isEmpty == true ? false : autoUpdate;

  String get realLabel => label.takeFirstValid([id.toString()]);

  String get fileName => '$id.yaml';

  String get updatingKey => 'profile_$id';

  Future<Profile?> checkAndUpdateAndCopy() async {
    final mFile = await _getFile(false);
    final isExists = await mFile.exists();
    if (isExists || url.isEmpty) {
      return null;
    }
    return update();
  }

  Future<File> _getFile([bool autoCreate = true]) async {
    final path = await appPath.getProfilePath(id.toString());
    final file = File(path);
    final isExists = await file.exists();
    if (!isExists && autoCreate) {
      return file.create(recursive: true);
    }
    return file;
    // final oldPath = await appPath.getProfilePath(id);
    // final newPath = await appPath.getProfilePath(fileName);
    // final oldFile = oldPath == newPath ? null : File(oldPath);
    // final oldIsExists = await oldFile?.exists() ?? false;
    // if (oldIsExists) {
    //   return await oldFile!.rename(newPath);
    // }
    // final file = File(newPath);
    // final isExists = await file.exists();
    // if (!isExists && autoCreate) {
    //   return await file.create(recursive: true);
    // }
    // return file;
  }

  Future<File> get file async {
    return _getFile();
  }

  Future<Profile> update() async {
    commonPrint.log('[profile-sync-model] fetch start id=$id url=$url');
    commonPrint.log('[profile-sync-model] request start id=$id direct=true');
    final response = await request.getFileResponseForUrl(
      url,
      direct: true,
      subscriptionCompatible: true,
    );
    commonPrint.log(
      '[profile-sync-model] request returned id=$id status=${response.statusCode} bytes=${response.data?.length ?? 0}',
    );
    final disposition = response.headers.value('content-disposition');
    final profileTitle = response.headers.value('profile-title');
    final userinfo = response.headers.value('subscription-userinfo');
    final uri = Uri.tryParse(url);
    final fallbackLabel = label.takeFirstValid([
      profileTitle,
      utils.getFileNameForDisposition(disposition),
      uri?.host,
      id.toString(),
    ]);
    final next = copyWith(
      label: fallbackLabel,
      subscriptionInfo: SubscriptionInfo.formHString(userinfo),
    );
    commonPrint.log(
      '[profile-sync-model] fetch done id=$id bytes=${response.data?.length ?? 0} disposition=$disposition profileTitle=$profileTitle userinfo=${userinfo != null} label=$fallbackLabel',
    );
    return next.saveFile(response.data ?? Uint8List.fromList([]));
  }

  Future<Profile> saveFile(Uint8List bytes) async {
    bytes = normalizeImportedConfigBytes(bytes);
    final path = await appPath.coreSafeTempFilePath;
    final tempFile = File(path);
    await tempFile.safeWriteAsBytes(bytes);
    var message = await coreController.validateConfig(path);
    if (message.isNotEmpty) {
      final converted = await coreController.convertSubscription(
        String.fromCharCodes(bytes),
      );
      if (converted.isNotEmpty) {
        await tempFile.safeWriteAsString(converted);
        message = await coreController.validateConfig(path);
      }
    }
    if (message.isNotEmpty) {
      throw message;
    }
    final mFile = await file;
    await tempFile.copy(mFile.path);
    await tempFile.safeDelete();
    return copyWith(lastUpdateDate: DateTime.now());
  }

  Future<Profile> saveFileWithPath(String path) async {
    final message = await coreController.validateConfig(path);
    if (message.isNotEmpty) {
      throw message;
    }
    final mFile = await file;
    await File(path).copy(mFile.path);
    return copyWith(lastUpdateDate: DateTime.now());
  }
}
