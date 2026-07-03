import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqlite3/open.dart' as sqlite_open;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

Future<T> decodeJSONTask<T>(String data) async {
  return compute<String, T>(_decodeJSON, data);
}

Future<T> _decodeJSON<T>(String content) async {
  return json.decode(content);
}

Future<String> encodeJSONTask<T>(T data) async {
  return compute<T, String>(_encodeJSON, data);
}

Future<String> _encodeJSON<T>(T content) async {
  return json.encode(content);
}

Future<String> encodeYamlTask<T>(T data) async {
  return compute<T, String>(_encodeYaml, data);
}

Future<String> _encodeYaml<T>(T content) async {
  return yaml.encode(content);
}

Future<String> encodeMD5Task(String data) async {
  return compute<String, String>(_encodeMD5, data);
}

Future<String> _encodeMD5<T>(String content) async {
  return content.toMd5();
}

Future<List<Group>> toGroupsTask(ComputeGroupsState data) async {
  return compute<ComputeGroupsState, List<Group>>(_toGroupsTask, data);
}

Future<List<Group>> _toGroupsTask(ComputeGroupsState state) async {
  final proxiesData = state.proxiesData;
  final all = proxiesData.all;
  final sortType = state.sortType;
  final delayMap = state.delayMap;
  final selectedMap = state.selectedMap;
  final defaultTestUrl = state.defaultTestUrl;
  final proxies = proxiesData.proxies;
  if (proxies.isEmpty) return [];
  final groupsRaw = all
      .where((name) {
        final proxy = proxies[name] ?? {};
        return GroupTypeExtension.valueList.contains(proxy['type']);
      })
      .map((groupName) {
        final group = proxies[groupName];
        group['all'] = ((group['all'] ?? []) as List)
            .map((name) => proxies[name])
            .where((proxy) => proxy != null)
            .toList();
        return group;
      })
      .toList();
  final groups = groupsRaw.map((e) => Group.fromJson(e)).toList();
  return computeSort(
    groups: groups,
    sortType: sortType,
    delayMap: delayMap,
    selectedMap: selectedMap,
    defaultTestUrl: defaultTestUrl,
  );
}

Future<VM2<String, String>> makeRealProfileTask(
  MakeRealProfileState data,
) async {
  return compute<MakeRealProfileState, VM2<String, String>>(
    _makeRealProfileTask,
    data,
  );
}

Future<VM2<String, String>> _makeRealProfileTask(
  MakeRealProfileState data,
) async {
  final rawConfig = Map.from(data.rawConfig);
  final realPatchConfig = data.realPatchConfig;
  final profilesPath = data.profilesPath;
  final profileId = data.profileId;
  final overrideDns = data.overrideDns;
  final addedRules = data.addedRules;
  final appendSystemDns = data.appendSystemDns;
  final defaultUA = data.defaultUA;
  String getProvidersFilePathInner(String type, String url) {
    return join(
      profilesPath,
      'providers',
      profileId.toString(),
      type,
      url.toMd5(),
    );
  }

  rawConfig['external-controller'] = realPatchConfig.externalController.value;
  rawConfig['external-ui'] = '';
  rawConfig['interface-name'] = '';
  rawConfig['external-ui-url'] = '';
  rawConfig['tcp-concurrent'] = realPatchConfig.tcpConcurrent;
  rawConfig['unified-delay'] = realPatchConfig.unifiedDelay;
  rawConfig['ipv6'] = realPatchConfig.ipv6;
  rawConfig['log-level'] = realPatchConfig.logLevel.name;
  rawConfig['port'] = 0;
  rawConfig['socks-port'] = 0;
  rawConfig['keep-alive-interval'] = realPatchConfig.keepAliveInterval;
  rawConfig['mixed-port'] = realPatchConfig.mixedPort;
  rawConfig['port'] = realPatchConfig.port;
  rawConfig['socks-port'] = realPatchConfig.socksPort;
  rawConfig['redir-port'] = realPatchConfig.redirPort;
  rawConfig['tproxy-port'] = realPatchConfig.tproxyPort;
  rawConfig['find-process-mode'] = realPatchConfig.findProcessMode.name;
  rawConfig['allow-lan'] = realPatchConfig.allowLan;
  rawConfig['mode'] = realPatchConfig.mode.name;
  if (rawConfig['tun'] == null) {
    rawConfig['tun'] = {};
  }
  rawConfig['tun']['enable'] = realPatchConfig.tun.enable;
  rawConfig['tun']['device'] = realPatchConfig.tun.device;
  rawConfig['tun']['dns-hijack'] = realPatchConfig.tun.dnsHijack;
  rawConfig['tun']['stack'] = realPatchConfig.tun.stack.name;
  rawConfig['tun']['route-address'] = realPatchConfig.tun.routeAddress;
  rawConfig['tun']['auto-route'] = realPatchConfig.tun.autoRoute;
  rawConfig['geodata-loader'] = realPatchConfig.geodataLoader.name;
  if (rawConfig['sniffer']?['sniff'] != null) {
    for (final value in (rawConfig['sniffer']?['sniff'] as Map).values) {
      if (value['ports'] != null && value['ports'] is List) {
        value['ports'] =
            value['ports']?.map((item) => item.toString()).toList() ?? [];
      }
    }
  }
  if (rawConfig['profile'] == null) {
    rawConfig['profile'] = {};
  }
  if (rawConfig['proxy-providers'] != null) {
    final proxyProviders = rawConfig['proxy-providers'] as Map;
    for (final key in proxyProviders.keys) {
      final proxyProvider = proxyProviders[key];
      if (proxyProvider['type'] != 'http') {
        continue;
      }
      if (proxyProvider['url'] != null) {
        proxyProvider['path'] = getProvidersFilePathInner(
          'proxies',
          proxyProvider['url'],
        );
      }
    }
  }
  if (rawConfig['rule-providers'] != null) {
    final ruleProviders = rawConfig['rule-providers'] as Map;
    for (final key in ruleProviders.keys) {
      final ruleProvider = ruleProviders[key];
      if (ruleProvider['type'] != 'http') {
        continue;
      }
      if (ruleProvider['url'] != null) {
        ruleProvider['path'] = getProvidersFilePathInner(
          'rules',
          ruleProvider['url'],
        );
      }
    }
  }
  rawConfig['profile']['store-selected'] = false;
  rawConfig['geox-url'] = realPatchConfig.geoXUrl.toJson();
  rawConfig['global-ua'] = realPatchConfig.globalUa ?? defaultUA;
  if (rawConfig['hosts'] == null) {
    rawConfig['hosts'] = {};
  }
  for (final host in realPatchConfig.hosts.entries) {
    rawConfig['hosts'][host.key] = host.value.splitByMultipleSeparators;
  }
  if (rawConfig['dns'] == null) {
    rawConfig['dns'] = {};
  }
  final isEnableDns = rawConfig['dns']['enable'] == true;
  const systemDns = 'system://';
  if (overrideDns || !isEnableDns) {
    final dns = switch (!isEnableDns) {
      true => realPatchConfig.dns.copyWith(
        nameserver: [...realPatchConfig.dns.nameserver, systemDns],
      ),
      false => realPatchConfig.dns,
    };
    rawConfig['dns'] = dns.toJson();
    rawConfig['dns']['nameserver-policy'] = {};
    for (final entry in dns.nameserverPolicy.entries) {
      rawConfig['dns']['nameserver-policy'][entry.key] =
          entry.value.splitByMultipleSeparators;
    }
  }
  if (appendSystemDns) {
    final List<String> nameserver = List<String>.from(
      rawConfig['dns']['nameserver'] ?? [],
    );
    if (!nameserver.contains(systemDns)) {
      rawConfig['dns']['nameserver'] = [...nameserver, systemDns];
    }
  }
  if (system.isOhos) {
    rawConfig['profile'] = normalizeOhosProfileConfig(
      rawConfig['profile'] as Map? ?? const {},
    );
    rawConfig['dns'] = normalizeOhosDnsConfig(
      rawConfig['dns'] as Map? ?? const {},
      realPatchConfig.dns,
    );
    rawConfig['tun']['dns-hijack'] = normalizeOhosTunDnsHijack(
      List<String>.from(rawConfig['tun']['dns-hijack'] ?? const []),
    );
    rawConfig['log-level'] = 'info';
  }
  List<String> rules = [];
  if (data.rules.isEmpty) {
    if (rawConfig['rules'] != null) {
      rules = List<String>.from(rawConfig['rules']);
    }
    if (addedRules.isNotEmpty) {
      final hasMatchPlaceholder = addedRules.any(
        (item) => item.ruleTarget?.toUpperCase() == 'MATCH',
      );
      String? replacementTarget;

      if (hasMatchPlaceholder) {
        for (int i = rules.length - 1; i >= 0; i--) {
          final parsed = Rule.parse(rules[i]);
          if (parsed.ruleAction == RuleAction.MATCH) {
            final target = parsed.ruleTarget;
            if (target != null && target.isNotEmpty) {
              replacementTarget = target;
              break;
            }
          }
        }
      }
      final List<String> finalAddedRules;

      if (replacementTarget?.isNotEmpty == true) {
        finalAddedRules = [];
        for (int i = 0; i < addedRules.length; i++) {
          final parsed = addedRules[i];
          if (parsed.ruleTarget?.toUpperCase() == 'MATCH') {
            finalAddedRules.add(
              parsed.copyWith(ruleTarget: replacementTarget).rawValue,
            );
          } else {
            finalAddedRules.add(addedRules[i].rawValue);
          }
        }
      } else {
        finalAddedRules = addedRules.map((e) => e.rawValue).toList();
      }
      rules = [...finalAddedRules, ...rules];
    }
  } else {
    rules = data.rules.map((item) => item.rawValue).toList();
  }
  if (system.isOhos) {
    rules = prependOhosDirectRules(rules);
  }
  if (data.proxyGroups.isNotEmpty) {
    rawConfig['proxy-groups'] = data.proxyGroups;
  }
  rawConfig['rules'] = rules;
  final yaml = await _encodeYaml(Map<String, dynamic>.from(rawConfig));
  return VM2(yaml, yaml.toMd5());
}

Map<String, dynamic> normalizeOhosDnsConfig(Map dnsConfig, Dns patchDns) {
  const ohosDirectSystemDns = 'system://';
  final normalized = Map<String, dynamic>.from(dnsConfig);
  normalized['listen'] = patchDns.listen.isEmpty
      ? defaultDns.listen
      : patchDns.listen;
  if ((normalized['enable'] as bool?) != true) {
    normalized['enable'] = true;
  }
  final nameserver = List<String>.from(normalized['nameserver'] ?? const []);
  final fallback = List<String>.from(normalized['fallback'] ?? const []);
  final patchFallback = patchDns.fallback;
  if (fallback.isEmpty && patchFallback.isNotEmpty) {
    normalized['fallback'] = patchFallback;
  }
  if (_shouldPreferOhosFallbackResolvers(nameserver, patchDns)) {
    normalized['nameserver'] = List<String>.from(
      fallback.isNotEmpty ? fallback : patchFallback,
    );
  } else if (nameserver.isEmpty) {
    normalized['nameserver'] = patchDns.nameserver;
  }
  final ohosDirectResolvers = _resolveOhosBootstrapDnsResolvers(
    normalized,
    patchDns,
  );
  final directNameserver = List<String>.from(
    normalized['direct-nameserver'] ?? const [],
  );
  if (directNameserver.isEmpty) {
    normalized['direct-nameserver'] = [ohosDirectSystemDns];
    normalized['direct-nameserver-follow-policy'] = false;
  }
  final nameserverPolicy = Map<String, dynamic>.from(
    normalized['nameserver-policy'] ?? const <String, dynamic>{},
  );
  for (final domain in _ohosHuaweiSystemDnsDomains) {
    nameserverPolicy.putIfAbsent(domain, () => ohosDirectResolvers);
  }
  normalized['nameserver-policy'] = nameserverPolicy;
  final fakeIpFilter = List<String>.from(
    normalized['fake-ip-filter'] ?? const <String>[],
  );
  for (final domain in _ohosHuaweiFakeIpFilterDomains) {
    if (fakeIpFilter.contains(domain)) {
      continue;
    }
    fakeIpFilter.add(domain);
  }
  normalized['fake-ip-filter'] = fakeIpFilter;
  return normalized;
}

bool _shouldPreferOhosFallbackResolvers(
  List<String> nameserver,
  Dns patchDns,
) {
  if (nameserver.isEmpty) {
    return false;
  }
  final patchFallback = patchDns.fallback;
  if (patchFallback.isEmpty) {
    return false;
  }
  final normalizedNameserver = nameserver
      .map((item) => item.trim())
      .where((item) => item != 'system://')
      .toList();
  final normalizedPatchNameserver = patchDns.nameserver
      .map((item) => item.trim())
      .toList();
  if (normalizedNameserver.length != normalizedPatchNameserver.length) {
    return false;
  }
  for (var i = 0; i < normalizedNameserver.length; i++) {
    if (normalizedNameserver[i] != normalizedPatchNameserver[i]) {
      return false;
    }
  }
  return true;
}

List<String> _resolveOhosBootstrapDnsResolvers(
  Map<String, dynamic> dnsConfig,
  Dns patchDns,
) {
  const systemDns = 'system://';
  final resolvers = <String>[];

  void addAll(dynamic source) {
    for (final item in List<String>.from(source ?? const <String>[])) {
      if (item.isEmpty || item == systemDns || resolvers.contains(item)) {
        continue;
      }
      resolvers.add(item);
    }
  }

  addAll(dnsConfig['default-nameserver']);
  addAll(patchDns.defaultNameserver);
  if (resolvers.isEmpty) {
    addAll(dnsConfig['direct-nameserver']);
  }
  if (resolvers.isEmpty) {
    addAll(dnsConfig['nameserver']);
    addAll(patchDns.nameserver);
  }
  return resolvers.isEmpty ? [systemDns] : resolvers;
}

List<String> prependOhosDirectRules(List<String> rules) {
  final remainingRules = List<String>.from(rules);
  final prependedRules = <String>[];
  for (final rule in _ohosHuaweiDirectRules) {
    if (remainingRules.remove(rule)) {
      prependedRules.add(rule);
      continue;
    }
    prependedRules.add(rule);
  }
  return [...prependedRules, ...remainingRules];
}

List<String> normalizeOhosTunDnsHijack(List<String> dnsHijack) {
  if (dnsHijack.isEmpty) {
    return ['0.0.0.0:53'];
  }
  final normalized = <String>[];
  for (final item in dnsHijack) {
    final value = item == 'any:53' ? '0.0.0.0:53' : item;
    if (normalized.contains(value)) {
      continue;
    }
    normalized.add(value);
  }
  return normalized;
}

Map<String, dynamic> normalizeOhosProfileConfig(Map profile) {
  final normalized = Map<String, dynamic>.from(profile);
  normalized['store-selected'] = false;
  normalized['store-fake-ip'] = false;
  return normalized;
}

const _ohosHuaweiSystemDnsDomains = [
  'browsercfg-drcn.cloud.dbankcloud.cn',
  'browserr-drcn.dbankcdn.cn',
  'configserver-drcn.platform.dbankcloud.cn',
  'httpdns.platform.dbankcloud.com',
  'httpdns-browser.platform.dbankcloud.cn',
  'contentcenter-drcn.cloud.dbankcloud.cn',
  'newsfeed-drcn.cloud.dbankcloud.cn',
  'nps-drcn.platform.dbankcloud.cn',
  'terms-drcn.platform.dbankcloud.cn',
  'metrics1-drcn.dt.dbankcloud.cn',
  'sdkserver-drcn.op.dbankcloud.cn',
  'feeds-drcn.cloud.huawei.com.cn',
  '+.grs.dbankcloud.cn',
  '+.grs.dbankcloud.com',
];

const _ohosHuaweiFakeIpFilterDomains = [
  'browsercfg-drcn.cloud.dbankcloud.cn',
  'browserr-drcn.dbankcdn.cn',
  'configserver-drcn.platform.dbankcloud.cn',
  'httpdns.platform.dbankcloud.com',
  'httpdns-browser.platform.dbankcloud.cn',
  'contentcenter-drcn.cloud.dbankcloud.cn',
  'newsfeed-drcn.cloud.dbankcloud.cn',
  'nps-drcn.platform.dbankcloud.cn',
  'terms-drcn.platform.dbankcloud.cn',
  'metrics1-drcn.dt.dbankcloud.cn',
  'sdkserver-drcn.op.dbankcloud.cn',
  'feeds-drcn.cloud.huawei.com.cn',
  '*.grs.dbankcloud.cn',
  '*.grs.dbankcloud.com',
];

const _ohosHuaweiDirectRules = [
  'IP-CIDR,139.9.98.98/32,DIRECT,no-resolve',
  'IP-CIDR,139.9.99.99/32,DIRECT,no-resolve',
  'DOMAIN,browsercfg-drcn.cloud.dbankcloud.cn,DIRECT',
  'DOMAIN,browserr-drcn.dbankcdn.cn,DIRECT',
  'DOMAIN,configserver-drcn.platform.dbankcloud.cn,DIRECT',
  'DOMAIN,httpdns.platform.dbankcloud.com,DIRECT',
  'DOMAIN,httpdns-browser.platform.dbankcloud.cn,DIRECT',
  'DOMAIN,contentcenter-drcn.cloud.dbankcloud.cn,DIRECT',
  'DOMAIN,newsfeed-drcn.cloud.dbankcloud.cn,DIRECT',
  'DOMAIN,nps-drcn.platform.dbankcloud.cn,DIRECT',
  'DOMAIN,terms-drcn.platform.dbankcloud.cn,DIRECT',
  'DOMAIN,metrics1-drcn.dt.dbankcloud.cn,DIRECT',
  'DOMAIN,sdkserver-drcn.op.dbankcloud.cn,DIRECT',
  'DOMAIN,feeds-drcn.cloud.huawei.com.cn,DIRECT',
];

Future<List<String>> shakingProfileTask(
  VM3<Iterable<int>, Iterable<int>, VM3<String, String, String>> data,
) async {
  return compute<
    VM4<
      Iterable<int>,
      Iterable<int>,
      VM3<String, String, String>,
      RootIsolateToken
    >,
    List<String>
  >(
    _shakingProfileTask,
    VM4(data.a, data.b, data.c, RootIsolateToken.instance!),
  );
}

Future<List<String>> _shakingProfileTask(
  VM4<
    Iterable<int>,
    Iterable<int>,
    VM3<String, String, String>,
    RootIsolateToken
  >
  data,
) async {
  final profileIds = data.a;
  final scriptIds = data.b;
  final profilesPath = data.c.a;
  final scriptsDirPath = data.c.b;
  final providersRootPath = data.c.c;
  final token = data.d;
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  final profilesDir = Directory(profilesPath);
  final scriptsDir = Directory(scriptsDirPath);
  final providersDir = Directory(providersRootPath);
  final List<String> targets = [];
  void scanDirectory(
    Directory dir,
    Iterable<int> baseNames, {
    bool skipProvidersFolder = false,
  }) {
    if (!dir.existsSync()) return;
    final entities = dir.listSync(recursive: false, followLinks: false);

    for (final entity in entities) {
      if (entity is File) {
        final id = basenameWithoutExtension(entity.path);
        if (!baseNames.contains(int.tryParse(id))) {
          targets.add(entity.path);
        }
      } else if (skipProvidersFolder && entity is Directory) {
        if (basename(entity.path) == 'providers') {
          continue;
        }
      }
    }
  }

  scanDirectory(profilesDir, profileIds, skipProvidersFolder: true);
  scanDirectory(providersDir, profileIds);
  scanDirectory(scriptsDir, scriptIds);
  return targets;
}

Future<String> encodeLogsTask(List<Log> data) async {
  return compute<List<Log>, String>(_encodeLogsTask, data);
}

Future<String> _encodeLogsTask(List<Log> data) async {
  final logsRaw = data.map((item) => item.toString());
  final logsRawString = logsRaw.join('\n');
  return logsRawString;
}

Future<MigrationData> oldToNowTask(Map<String, Object?> data) async {
  final homeDir = await appPath.homeDirPath;
  return compute<VM3<Map<String, Object?>, String, String>, MigrationData>(
    _oldToNowTask,
    VM3(data, homeDir, homeDir),
  );
}

Future<MigrationData> _oldToNowTask(
  VM3<Map<String, Object?>, String, String> data,
) async {
  final configMap = data.a;
  final sourcePath = data.b;
  final targetPath = data.c;

  final accessControlMap = configMap['accessControl'];
  final isAccessControl = configMap['isAccessControl'];
  if (accessControlMap != null) {
    (accessControlMap as Map)['enable'] = isAccessControl;
    if (configMap['vpnProps'] != null) {
      final vpnPropsRaw = configMap['vpnProps'] as Map;
      vpnPropsRaw['accessControl'] = accessControlMap;
    }
  }
  if (configMap['vpnProps'] != null) {
    final vpnPropsRaw = configMap['vpnProps'] as Map;
    vpnPropsRaw['accessControlProps'] = vpnPropsRaw['accessControl'];
  }
  configMap['davProps'] = configMap['dav'];
  final appSettingProps =
      configMap['appSetting'] as Map<String, dynamic>? ?? {};
  appSettingProps['restoreStrategy'] = appSettingProps['recoveryStrategy'];
  configMap['appSettingProps'] = appSettingProps;
  configMap['proxiesStyleProps'] = configMap['proxiesStyle'];
  configMap['proxiesStyleProps'] = configMap['proxiesStyle'];
  // final overwriteMap = configMap['overwrite'] as Map? ?? {};
  // configMap['overwriteType'] = overwriteMap['type'];
  // configMap['scriptId'] = overwriteMap['scriptOverwrite'];
  List rawScripts = configMap['scripts'] as List<dynamic>? ?? [];
  if (rawScripts.isEmpty) {
    final scriptPropsJson = configMap['scriptProps'] as Map<String, dynamic>?;
    if (scriptPropsJson != null) {
      rawScripts = scriptPropsJson['scripts'] as List<dynamic>? ?? [];
    }
  }
  final Map<String, int> idMap = {};
  final List<Script> scripts = [];
  for (final rawScript in rawScripts) {
    final id = rawScript['id'] as String?;
    final content = rawScript['content'] as String?;
    final label = rawScript['label'] as String?;
    if (id == null || content == null || label == null) {
      continue;
    }
    final newId = idMap.updateCacheValue(rawScript['id'], () => snowflake.id);
    final path = _getScriptPath(targetPath, newId.toString());
    final file = File(path);
    await file.safeWriteAsString(content);
    scripts.add(
      Script(id: newId, label: label, lastUpdateTime: DateTime.now()),
    );
  }
  final List rawRules = configMap['rules'] as List<dynamic>? ?? [];
  final List<Rule> rules = [];
  final List<ProfileRuleLink> links = [];
  for (final rawRule in rawRules) {
    final id = idMap.updateCacheValue(rawRule['id'], () => snowflake.id);
    rawRule['id'] = id;
    final value = rawRule['value'] ?? '';
    rules.add(Rule.parse(value, id: id));
    links.add(ProfileRuleLink(ruleId: id));
  }
  final List rawProfiles = configMap['profiles'] as List<dynamic>? ?? [];
  final List<Profile> profiles = [];
  for (final rawProfile in rawProfiles) {
    final rawId = rawProfile['id'] as String?;
    if (rawId == null) {
      continue;
    }
    final profileId = idMap.updateCacheValue(rawId, () => snowflake.id);
    rawProfile['id'] = profileId;
    final overwrite = rawProfile['overwrite'] as Map?;
    if (overwrite != null) {
      final standardOverwrite = overwrite['standardOverwrite'] as Map?;
      if (standardOverwrite != null) {
        final addedRules = standardOverwrite['addedRules'] as List? ?? [];
        for (final addRule in addedRules) {
          final id = idMap.updateCacheValue(addRule['id'], () => snowflake.id);
          final value = addRule['value'] ?? '';
          rules.add(Rule.parse(value, id: id));
          links.add(
            ProfileRuleLink(
              profileId: profileId,
              ruleId: id,
              scene: RuleScene.added,
            ),
          );
        }
        final disabledRuleIds = standardOverwrite['disabledRuleIds'] as List?;
        if (disabledRuleIds != null) {
          for (final disabledRuleId in disabledRuleIds) {
            final newDisabledRuleId = idMap[disabledRuleId];
            if (newDisabledRuleId != null) {
              links.add(
                ProfileRuleLink(
                  profileId: profileId,
                  ruleId: newDisabledRuleId,
                  scene: RuleScene.disabled,
                ),
              );
            }
          }
        }
      }
      final scriptOverwrite = overwrite['scriptOverwrite'] as Map?;
      if (scriptOverwrite != null) {
        final scriptId = scriptOverwrite['scriptId'] as String?;
        rawProfile['scriptId'] = scriptId != null ? idMap[scriptId] : null;
      }
      rawProfile['overwriteType'] = overwrite['type'];
    }

    final sourceFile = File(_getProfilePath(sourcePath, rawId));
    final targetFilePath = _getProfilePath(targetPath, profileId.toString());
    await sourceFile.safeCopy(targetFilePath);
    profiles.add(Profile.fromJson(rawProfile));
  }
  final currentProfileId = configMap['currentProfileId'];
  configMap['currentProfileId'] = currentProfileId != null
      ? idMap[currentProfileId]
      : null;
  return MigrationData(
    configMap: configMap,
    profiles: profiles,
    rules: rules,
    scripts: scripts,
    links: links,
  );
}

Future<String> backupTask(
  Map<String, dynamic> configMap,
  Iterable<String> fileNames,
) async {
  final tempRootPath = await appPath.tempPath;
  final args = <String, dynamic>{
    'configMap': configMap,
    'fileNames': fileNames.toList(),
    'dbPath': await appPath.databasePath,
    'profilesPath': await appPath.profilesPath,
    'scriptsPath': await appPath.scriptsDirPath,
    'tempZipFilePath': join(tempRootPath, 'backup-${utils.id}.zip'),
    'tempDBFilePath': join(tempRootPath, 'backup-${utils.id}.db'),
    'tempConfigFilePath': join(tempRootPath, 'backup-${utils.id}.json'),
  };
  return compute<VM2<Map<String, dynamic>, RootIsolateToken>, String>(
    _backupTask,
    VM2(args, RootIsolateToken.instance!),
  );
}

Future<String> _backupTask(
  VM2<Map<String, dynamic>, RootIsolateToken> args,
) async {
  final params = args.a;
  final token = args.b;
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  final configMap = Map<String, dynamic>.from(params['configMap'] as Map);
  final fileNames = (params['fileNames'] as List).cast<String>();
  final dbPath = params['dbPath'] as String;
  final configStr = json.encode(configMap);
  final profilesDir = Directory(params['profilesPath'] as String);
  final scriptsDir = Directory(params['scriptsPath'] as String);
  final tempZipFilePath = params['tempZipFilePath'] as String;
  final tempDBFile = File(params['tempDBFilePath'] as String);
  final tempConfigFile = File(params['tempConfigFilePath'] as String);
  final dbFile = File(dbPath);
  if (await dbFile.exists()) {
    await dbFile.copy(tempDBFile.path);
  }
  final encoder = ZipFileEncoder();
  encoder.create(tempZipFilePath);
  await tempConfigFile.writeAsString(configStr);
  await encoder.addFile(tempDBFile, backupDatabaseName);
  await encoder.addFile(tempConfigFile, configJsonName);
  if (await profilesDir.exists()) {
    await encoder.addDirectory(
      profilesDir,
      filter: (file, _) {
        if (!fileNames.contains(basename(file.path))) {
          return ZipFileOperation.skip;
        }
        return ZipFileOperation.include;
      },
    );
  }
  if (await scriptsDir.exists()) {
    await encoder.addDirectory(
      scriptsDir,
      filter: (file, _) {
        if (!fileNames.contains(basename(file.path))) {
          return ZipFileOperation.skip;
        }
        return ZipFileOperation.include;
      },
    );
  }
  encoder.close();
  await tempConfigFile.safeDelete();
  await tempDBFile.safeDelete();
  return tempZipFilePath;
}

Future<MigrationData> restoreTask() async {
  final args = <String, String>{
    'backupFilePath': await appPath.backupFilePath,
    'restoreDirPath': await appPath.restoreDirPath,
    'homeDirPath': await appPath.homeDirPath,
  };
  return compute<VM2<Map<String, String>, RootIsolateToken>, MigrationData>(
    _restoreTask,
    VM2(args, RootIsolateToken.instance!),
  );
}

Future<MigrationData> _restoreTask(
  VM2<Map<String, String>, RootIsolateToken> args,
) async {
  final params = args.a;
  final token = args.b;
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  final backupFilePath = params['backupFilePath']!;
  final restoreDirPath = params['restoreDirPath']!;
  final homeDirPath = params['homeDirPath']!;
  final zipDecoder = ZipDecoder();
  final input = InputFileStream(backupFilePath);
  final archive = zipDecoder.decodeStream(input);
  final dir = Directory(restoreDirPath);
  await dir.create(recursive: true);
  for (final file in archive.files) {
    final normalizedPath = posix.normalize(file.name);
    if (normalizedPath.isEmpty ||
        normalizedPath == '.' ||
        normalizedPath == '..') {
      continue;
    }
    final outPath = join(restoreDirPath, normalizedPath);
    if (file.isFile && !normalizedPath.endsWith('/')) {
      await Directory(dirname(outPath)).create(recursive: true);
      final outputStream = OutputFileStream(outPath);
      file.writeContent(outputStream);
      await outputStream.close();
      continue;
    }
    await Directory(outPath).create(recursive: true);
  }
  await input.close();
  final restoreConfigFile = File(join(restoreDirPath, configJsonName));
  if (!await restoreConfigFile.exists()) {
    throw StateError('invalid backup file');
  }
  final restoreConfigMap =
      json.decode(await restoreConfigFile.readAsString())
          as Map<String, Object?>?;
  final version = restoreConfigMap?['version'] ?? 0;
  MigrationData migrationData = MigrationData(configMap: restoreConfigMap);
  if (version == 0 && restoreConfigMap != null) {
    migrationData = await _oldToNowTask(
      VM3(restoreConfigMap, restoreDirPath, homeDirPath),
    );
    return migrationData;
  }
  final backupDatabaseFile = File(join(restoreDirPath, backupDatabaseName));
  if (!await backupDatabaseFile.exists()) {
    return migrationData;
  }
  if (system.isOhos) {
    sqlite_open.open.overrideForAll(() => DynamicLibrary.open('libsqlite3.so'));
    sqlite3.sqlite3.tempDirectory = '/data/storage/el2/base/temp';
  }
  final database = Database(NativeDatabase(backupDatabaseFile));
  final results = await Future.wait([
    database.profilesDao.query().get(),
    database.scriptsDao.query().get(),
    database.rules.all().map((item) => item.toRule()).get(),
    database.profileRuleLinks.all().map((item) => item.toLink()).get(),
    database.proxyGroups.all().map((item) => item.toProxyGroup()).get(),
  ]);
  final profiles = results[0].cast<Profile>();
  final scripts = results[1].cast<Script>();
  final profilesMigration = profiles.map(
    (item) => VM2(
      _getProfilePath(restoreDirPath, item.id.toString()),
      _getProfilePath(homeDirPath, item.id.toString()),
    ),
  );
  final scriptsMigration = scripts.map(
    (item) => VM2(
      _getScriptPath(restoreDirPath, item.id.toString()),
      _getScriptPath(homeDirPath, item.id.toString()),
    ),
  );
  await _copyWithMapList([...profilesMigration, ...scriptsMigration]);
  migrationData = migrationData.copyWith(
    profiles: profiles,
    scripts: scripts,
    rules: results[2].cast<Rule>(),
    links: results[3].cast<ProfileRuleLink>(),
    proxyGroups: results[4].cast<ProxyGroup>(),
  );
  await database.close();
  return migrationData;
}

Future<void> _copyWithMapList(List<VM2<String, String>> copyMapList) async {
  await Future.wait(
    copyMapList.map((item) => File(item.a).safeCopy(item.b)).toList(),
  );
}

String _getScriptPath(String root, String fileName) {
  return join(root, 'scripts', '$fileName.js');
}

String _getProfilePath(String root, String fileName) {
  return join(root, 'profiles', '$fileName.yaml');
}

Future<List<T>> mapListTask<T, S>(List<S> results, T Function(S) mapper) async {
  return compute<VM2<List<S>, T Function(S)>, List<T>>(
    _mapListTask,
    VM2(results, mapper),
  );
}

Future<List<T>> _mapListTask<T, S>(VM2<List<S>, T Function(S)> vm2) async {
  final results = vm2.a;
  final mapper = vm2.b;
  return results.map((item) => mapper(item)).toList();
}
