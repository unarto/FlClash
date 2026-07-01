import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/list.dart';
import 'package:fl_clash/widgets/scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class Contributor {
  final String avatar;
  final String name;
  final String link;

  const Contributor({
    required this.avatar,
    required this.name,
    required this.link,
  });
}

class AboutView extends StatelessWidget {
  const AboutView({super.key});

  Future<void> _importQrTestImage(BuildContext context) async {
    if (!system.isOhos) {
      return;
    }
    try {
      final bytes = await rootBundle.load('assets/images/jisu_qr_test.png');
      final path = '${await appPath.tempPath}/jisu_qr_test.png';
      await File(path).safeWriteAsBytes(bytes.buffer.asUint8List());
      final prepared = await app?.prepareGalleryTestImage(
        path,
        title: 'flclash_qr_test',
      );
      final imported = prepared == null
          ? null
          : await app?.importImageToGallery(prepared, title: 'flclash_qr_test');
      if (context.mounted) {
        context.showNotifier(imported == null ? '导入图库失败' : '已导入图库');
      }
    } catch (_) {
      if (context.mounted) {
        context.showNotifier('导入图库失败');
      }
    }
  }

  Future<void> _checkUpdate(BuildContext context) async {
    final result = await globalState.safeRun<CheckForUpdateResult>(
      request.checkForUpdate,
      title: context.appLocalizations.checkUpdate,
    );
    if (result == null) {
      return;
    }
    globalState.container
        .read(commonActionProvider.notifier)
        .checkUpdateResultHandle(result: result, isUser: true);
  }

  void _enableDeveloperMode(WidgetRef ref, BuildContext context) {
    commonPrint.log('[developer-mode] onEnterDeveloperMode invoked');
    ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(developerMode: true));
    commonPrint.log('[developer-mode] developerMode persisted=true');
    context.showNotifier(context.appLocalizations.developerModeEnableTip);
  }

  List<Widget> _buildMoreSection(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final items = <Widget>[
      if (globalState.isPre && system.isOhos)
        ListItem(
          title: const Text('导入二维码测试图到图库'),
          onTap: () {
            _importQrTestImage(context);
          },
        ),
      if (globalState.isPre && system.isOhos)
        Consumer(
          builder: (context, ref, _) {
            final enabled = ref.watch(
              appSettingProvider.select((state) => state.developerMode),
            );
            if (enabled) {
              return Container();
            }
            return ListItem(
              title: Text(appLocalizations.developerMode),
              subtitle: const Text('OHOS 模拟器显式入口，用于验证开发者页面功能'),
              onTap: () {
                _enableDeveloperMode(ref, context);
              },
            );
          },
        ),
      ListItem(
        title: Text(appLocalizations.checkUpdate),
        onTap: () {
          _checkUpdate(context);
        },
      ),
      ListItem(
        title: const Text('Telegram'),
        onTap: () {
          commonPrint.log('[about-link] tap telegram');
          globalState.openUrl('https://t.me/FlClash');
        },
        trailing: const Icon(Icons.launch),
      ),
      ListItem(
        title: Text(appLocalizations.project),
        onTap: () {
          commonPrint.log('[about-link] tap project');
          globalState.openUrl('https://github.com/$repository');
        },
        trailing: const Icon(Icons.launch),
      ),
      ListItem(
        title: Text(appLocalizations.core),
        onTap: () {
          commonPrint.log('[about-link] tap core');
          globalState.openUrl(
            'https://github.com/chen08209/Clash.Meta/tree/FlClash',
          );
        },
        trailing: const Icon(Icons.launch),
      ),
    ];
    return generateSection(
      separated: false,
      title: appLocalizations.more,
      items: items,
    );
  }

  List<Widget> _buildContributorsSection(AppLocalizations appLocalizations) {
    const contributors = [
      Contributor(
        avatar: 'assets/images/avatar/june2.jpg',
        name: 'June2',
        link: 'https://t.me/Jibadong',
      ),
      Contributor(
        avatar: 'assets/images/avatar/arue.jpg',
        name: 'Arue',
        link: 'https://t.me/xrcm6868',
      ),
    ];
    return generateSection(
      separated: false,
      title: appLocalizations.otherContributors,
      items: [
        ListItem(
          title: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Wrap(
              spacing: 24,
              children: [
                for (final contributor in contributors)
                  Avatar(contributor: contributor),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final items = [
      ListTile(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Consumer(
              builder: (_, ref, _) {
                return _DeveloperModeDetector(
                  child: Wrap(
                    spacing: 16,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Image.asset(
                          'assets/images/icon.png',
                          width: 64,
                          height: 64,
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            appName,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          Text(
                            globalState.packageInfo.version,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ],
                      ),
                    ],
                  ),
                  onEnterDeveloperMode: () {
                    _enableDeveloperMode(ref, context);
                  },
                );
              },
            ),
            const SizedBox(height: 24),
            Text(
              appLocalizations.desc,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      ..._buildContributorsSection(appLocalizations),
      ..._buildMoreSection(context),
    ];
    return BaseScaffold(
      title: appLocalizations.about,
      body: Padding(
        padding: kMaterialListPadding.copyWith(top: 16, bottom: 16),
        child: generateListView(items),
      ),
    );
  }
}

class Avatar extends StatelessWidget {
  final Contributor contributor;

  const Avatar({super.key, required this.contributor});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      child: Column(
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: CircleAvatar(
              foregroundImage: AssetImage(contributor.avatar),
            ),
          ),
          const SizedBox(height: 4),
          Text(contributor.name, style: context.textTheme.bodySmall),
        ],
      ),
      // onTap: () {
      //   globalState.openUrl(contributor.link);
      // },
    );
  }
}

class _DeveloperModeDetector extends StatefulWidget {
  final Widget child;
  final VoidCallback onEnterDeveloperMode;

  const _DeveloperModeDetector({
    required this.child,
    required this.onEnterDeveloperMode,
  });

  @override
  State<_DeveloperModeDetector> createState() => _DeveloperModeDetectorState();
}

class _DeveloperModeDetectorState extends State<_DeveloperModeDetector> {
  int _counter = 0;
  Timer? _timer;

  void _handleTap() {
    _counter++;
    commonPrint.log('[developer-mode] detector tap count=$_counter');
    if (_counter >= 5) {
      commonPrint.log('[developer-mode] detector threshold reached');
      widget.onEnterDeveloperMode();
      _resetCounter();
    } else {
      _timer?.cancel();
      _timer = Timer(const Duration(seconds: 1), _resetCounter);
    }
  }

  void _resetCounter() {
    commonPrint.log('[developer-mode] detector reset count=$_counter');
    _counter = 0;
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(onTap: _handleTap, child: widget.child);
  }
}
