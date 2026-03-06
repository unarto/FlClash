import 'dart:async';
import 'dart:io';

import 'package:fl_clash/controller.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tray_manager/tray_manager.dart';

import 'app_localizations.dart';
import 'constant.dart';
import 'system.dart';
import 'window.dart';

class Tray {
  static Tray? _instance;
  bool _keepMenuOpen = false;
  bool _pendingReopenOnClose = false;
  int _keepMenuOpenSessionId = 0;
  final Set<String> _delayTriggeredGroups = {};
  final Set<String> _testingProxyMenuKeys = {};
  final Map<String, int> _proxyMenuItemIdMap = {};
  final Map<String, int> _groupDelayActionItemIdMap = {};

  Tray._internal();

  factory Tray() {
    _instance ??= Tray._internal();
    return _instance!;
  }

  String get trayIconSuffix {
    return system.isWindows ? 'ico' : 'png';
  }

  Future<void> destroy() async {
    await trayManager.destroy();
  }

  String getTryIcon({required bool isStart, required bool tunEnable}) {
    if (system.isMacOS || !isStart) {
      return 'assets/images/icon/status_1.$trayIconSuffix';
    }
    if (!tunEnable) {
      return 'assets/images/icon/status_2.$trayIconSuffix';
    }
    return 'assets/images/icon/status_3.$trayIconSuffix';
  }

  Future _updateSystemTray({
    required bool isStart,
    required bool tunEnable,
  }) async {
    if (Platform.isLinux) {
      await trayManager.destroy();
    }
    await trayManager.setIcon(
      getTryIcon(isStart: isStart, tunEnable: tunEnable),
      isTemplate: true,
    );
    if (!Platform.isLinux) {
      await trayManager.setToolTip(appName);
    }
  }

  Future<void> update({
    required TrayState trayState,
    required Traffic traffic,
  }) async {
    if (system.isAndroid) {
      return;
    }
    if (!system.isLinux) {
      await _updateSystemTray(
        isStart: trayState.isStart,
        tunEnable: trayState.tunEnable,
      );
    }
    _proxyMenuItemIdMap.clear();
    _groupDelayActionItemIdMap.clear();
    List<MenuItem> menuItems = [];
    final showMenuItem = MenuItem(
      label: appLocalizations.show,
      onClick: (_) {
        window?.show();
      },
    );
    menuItems.add(showMenuItem);
    final startMenuItem = MenuItem.checkbox(
      label: trayState.isStart ? appLocalizations.stop : appLocalizations.start,
      onClick: (_) async {
        appController.updateStart();
      },
      checked: false,
    );
    menuItems.add(startMenuItem);
    if (system.isMacOS) {
      final speedStatistics = MenuItem.checkbox(
        label: appLocalizations.speedStatistics,
        onClick: (_) async {
          appController.updateSpeedStatistics();
        },
        checked: trayState.showTrayTitle,
      );
      menuItems.add(speedStatistics);
    }
    menuItems.add(MenuItem.separator());
    for (final mode in Mode.values) {
      menuItems.add(
        MenuItem.checkbox(
          label: Intl.message(mode.name),
          onClick: (_) {
            appController.changeMode(mode);
          },
          checked: mode == trayState.mode,
        ),
      );
    }
    menuItems.add(MenuItem.separator());
    if (system.isMacOS) {
      for (final group in trayState.groups) {
        List<MenuItem> subMenuItems = [];
        final testUrl = group.testUrl;
        final selectedProxyName = appController.getSelectedProxyName(group.name);
        final hasDelayResult =
            _hasDelayResultForGroup(group) ||
            _delayTriggeredGroups.contains(group.name);
        final delayActionItem = MenuItem(
          key: 'keep-open:delay-test:${group.name}',
          label: _buildDelayTestActionLabel(
            hasDelayResult: hasDelayResult,
          ),
          onClick: (_) {
            _startDelayTestAndKeepMenuOpen([group]);
          },
        );
        subMenuItems.add(delayActionItem);
        _groupDelayActionItemIdMap[group.name] = delayActionItem.id;
        subMenuItems.add(MenuItem.separator());
        final orderedProxies = _sortProxiesForTray(
          proxies: group.all,
          selectedProxyName: selectedProxyName,
        );
        for (final proxy in orderedProxies) {
          final proxyItem = MenuItem.checkbox(
            // 在 macOS 托盘菜单中直观展示当前测速结果。
            label: _buildProxyMenuLabel(
              proxy,
              groupName: group.name,
              testUrl: testUrl,
            ),
            checked: selectedProxyName == proxy.name,
            onClick: (_) {
              appController.updateCurrentSelectedMap(group.name, proxy.name);
              appController.changeProxy(
                groupName: group.name,
                proxyName: proxy.name,
              );
            },
          );
          subMenuItems.add(proxyItem);
          _proxyMenuItemIdMap[_buildProxyKey(
            groupName: group.name,
            proxyName: proxy.name,
            testUrl: testUrl,
          )] = proxyItem.id;
        }
        menuItems.add(
          MenuItem.submenu(
            label: group.name,
            submenu: Menu(items: subMenuItems),
          ),
        );
      }
      if (trayState.groups.isNotEmpty) {
        menuItems.add(MenuItem.separator());
      }
    }
    if (trayState.isStart) {
      menuItems.add(
        MenuItem.checkbox(
          label: appLocalizations.tun,
          onClick: (_) {
            appController.updateTun();
          },
          checked: trayState.tunEnable,
        ),
      );
      menuItems.add(
        MenuItem.checkbox(
          label: appLocalizations.systemProxy,
          onClick: (_) {
            appController.updateSystemProxy();
          },
          checked: trayState.systemProxy,
        ),
      );
      menuItems.add(MenuItem.separator());
    }
    final autoStartMenuItem = MenuItem.checkbox(
      label: appLocalizations.autoLaunch,
      onClick: (_) async {
        appController.updateAutoLaunch();
      },
      checked: trayState.autoLaunch,
    );
    final copyEnvVarMenuItem = MenuItem(
      label: appLocalizations.copyEnvVar,
      onClick: (_) async {
        await _copyEnv(trayState.port);
      },
    );
    menuItems.add(autoStartMenuItem);
    menuItems.add(copyEnvVarMenuItem);
    menuItems.add(MenuItem.separator());
    final exitMenuItem = MenuItem(
      label: appLocalizations.exit,
      onClick: (_) async {
        await appController.handleExit();
      },
    );
    menuItems.add(exitMenuItem);
    final menu = Menu(items: menuItems);
    await trayManager.setContextMenu(menu);
    if (system.isLinux) {
      await _updateSystemTray(
        isStart: trayState.isStart,
        tunEnable: trayState.tunEnable,
      );
    }
    updateTrayTitle(showTrayTitle: trayState.showTrayTitle, traffic: traffic);
    if (_keepMenuOpen) {
      // 菜单刷新会导致系统收起，这里登记一次“下次关闭后重开”。
      _pendingReopenOnClose = true;
    }
  }

  Future<void> updateTrayTitle({
    required bool showTrayTitle,
    required Traffic traffic,
  }) async {
    if (!system.isMacOS) {
      return;
    }
    if (!showTrayTitle) {
      await trayManager.setTitle('');
    } else {
      await trayManager.setTitle(traffic.trayTitle);
    }
  }

  Future<void> _copyEnv(int port) async {
    final url = 'http://127.0.0.1:$port';

    final cmdline = system.isWindows
        ? 'set \$env:all_proxy=$url'
        : 'export all_proxy=$url';

    await Clipboard.setData(ClipboardData(text: cmdline));
  }

  void _startDelayTestAndKeepMenuOpen(List<Group> groups) {
    final sessionId = ++_keepMenuOpenSessionId;
    _keepMenuOpen = true;
    _pendingReopenOnClose = false;
    for (final group in groups) {
      _delayTriggeredGroups.add(group.name);
      unawaited(_updateDelayActionLabel(group));
      for (final proxy in group.all) {
        _testingProxyMenuKeys.add(
          _buildProxyKey(
            groupName: group.name,
            proxyName: proxy.name,
            testUrl: group.testUrl,
          ),
        );
        unawaited(
          _updateProxyMenuLabel(
            groupName: group.name,
            proxyName: proxy.name,
            testUrl: group.testUrl,
          ),
        );
      }
    }
    unawaited(() async {
      try {
        await appController.delayTestForTrayGroups(
          groups,
          refreshTrayOnProgress: false,
          refreshTrayOnDone: false,
          onDelayUpdated: (proxyName, testUrl) {
            for (final group in groups) {
              if (group.testUrl != testUrl) {
                continue;
              }
              _testingProxyMenuKeys.remove(
                _buildProxyKey(
                  groupName: group.name,
                  proxyName: proxyName,
                  testUrl: group.testUrl,
                ),
              );
              unawaited(
                _updateProxyMenuLabel(
                  groupName: group.name,
                  proxyName: proxyName,
                  testUrl: group.testUrl,
                ),
              );
            }
          },
        );
      } finally {
        if (_keepMenuOpenSessionId == sessionId) {
          _keepMenuOpen = false;
          _pendingReopenOnClose = false;
        }
        for (final group in groups) {
          for (final proxy in group.all) {
            _testingProxyMenuKeys.remove(
              _buildProxyKey(
                groupName: group.name,
                proxyName: proxy.name,
                testUrl: group.testUrl,
              ),
            );
            unawaited(
              _updateProxyMenuLabel(
                groupName: group.name,
                proxyName: proxy.name,
                testUrl: group.testUrl,
              ),
            );
          }
        }
      }
    }());
  }

  void handleMenuDidClose() {
    if (!system.isMacOS || !_keepMenuOpen) {
      return;
    }
    if (!_pendingReopenOnClose) {
      _cancelKeepMenuOpen();
      return;
    }
    _pendingReopenOnClose = false;
    _reopenMenuIfSessionValid(_keepMenuOpenSessionId);
  }

  void _reopenMenuIfSessionValid(int sessionId) {
    if (!system.isMacOS || !_keepMenuOpen || _keepMenuOpenSessionId != sessionId) {
      return;
    }
    unawaited(trayManager.popUpContextMenu());
  }

  void _cancelKeepMenuOpen() {
    _keepMenuOpen = false;
    _pendingReopenOnClose = false;
  }

  List<Proxy> _sortProxiesForTray({
    required List<Proxy> proxies,
    required String? selectedProxyName,
  }) {
    if (selectedProxyName == null || selectedProxyName.isEmpty) {
      return proxies;
    }
    final sortedProxies = List<Proxy>.from(proxies);
    sortedProxies.sort((a, b) {
      if (a.name == selectedProxyName && b.name != selectedProxyName) {
        return -1;
      }
      if (b.name == selectedProxyName && a.name != selectedProxyName) {
        return 1;
      }
      return 0;
    });
    return sortedProxies;
  }

  String _buildProxyKey({
    required String groupName,
    required String proxyName,
    required String? testUrl,
  }) {
    return '$groupName|$proxyName|${testUrl ?? ''}';
  }

  Future<void> _updateDelayActionLabel(Group group) async {
    final itemId = _groupDelayActionItemIdMap[group.name];
    if (itemId == null) {
      return;
    }
    await trayManager.updateMenuItemLabel(
      id: itemId,
      label: _buildDelayTestActionLabel(
        hasDelayResult:
            _hasDelayResultForGroup(group) ||
            _delayTriggeredGroups.contains(group.name),
      ),
    );
  }

  Future<void> _updateProxyMenuLabel({
    required String groupName,
    required String proxyName,
    required String? testUrl,
  }) async {
    final itemId = _proxyMenuItemIdMap[_buildProxyKey(
      groupName: groupName,
      proxyName: proxyName,
      testUrl: testUrl,
    )];
    if (itemId == null) {
      return;
    }
    await trayManager.updateMenuItemLabel(
      id: itemId,
      label: _buildProxyMenuLabelByName(
        proxyName,
        testUrl: testUrl,
        testingKey: _buildProxyKey(
          groupName: groupName,
          proxyName: proxyName,
          testUrl: testUrl,
        ),
      ),
    );
  }

  String _buildProxyMenuLabel(
    Proxy proxy, {
    required String groupName,
    String? testUrl,
  }) {
    return _buildProxyMenuLabelByName(
      proxy.name,
      testUrl: testUrl,
      testingKey: _buildProxyKey(
        groupName: groupName,
        proxyName: proxy.name,
        testUrl: testUrl,
      ),
    );
  }

  String _buildProxyMenuLabelByName(
    String proxyName, {
    String? testUrl,
    String? testingKey,
  }) {
    if (testingKey != null && _testingProxyMenuKeys.contains(testingKey)) {
      return '$proxyName (...)';
    }
    final delay = appController.getDelayForProxy(proxyName, testUrl: testUrl);
    if (delay == null) {
      return proxyName;
    }
    final delayText = switch (delay) {
      0 => '...',
      > 0 => '$delay ms',
      _ => 'Timeout',
    };
    return '$proxyName ($delayText)';
  }

  bool _hasDelayResultForGroup(Group group) {
    for (final proxy in group.all) {
      final delay = appController.getDelayForProxy(
        proxy.name,
        testUrl: group.testUrl,
      );
      if (delay != null) {
        return true;
      }
    }
    return false;
  }

  String _buildDelayTestActionLabel({
    required bool hasDelayResult,
  }) {
    if (hasDelayResult) {
      return appLocalizations.retest;
    }
    return appLocalizations.delayTest;
  }
}

final tray = system.isDesktop ? Tray() : null;
