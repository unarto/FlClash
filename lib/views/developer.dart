import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/common.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DeveloperView extends ConsumerWidget {
  const DeveloperView({super.key});

  Future<void> _importQrTestImage(BuildContext context) async {
    if (!system.isOhos) {
      return;
    }
    final bytes = await rootBundle.load('assets/images/jisu_qr_test.png');
    final path = '${await appPath.tempPath}/jisu_qr_test.png';
    await File(path).safeWriteAsBytes(bytes.buffer.asUint8List());
    final prepared = await app?.prepareGalleryTestImage(
      path,
      title: 'flclash_qr_test',
    );
    final imported = prepared == null
        ? null
        : await app?.importImageToGallery(
            prepared,
            title: 'flclash_qr_test',
          );
    if (context.mounted) {
      context.showNotifier(imported == null ? '导入图库失败' : '已导入图库');
    }
  }

  Widget _getDeveloperList(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    return generateSectionV2(
      title: appLocalizations.options,
      items: [
        ListItem(
          title: Text(appLocalizations.messageTest),
          minVerticalPadding: 12,
          onTap: () {
            context.showNotifier(appLocalizations.messageTestTip);
          },
        ),
        ListItem(
          title: Text(appLocalizations.logsTest),
          minVerticalPadding: 12,
          onTap: () {
            for (int i = 0; i < 1000; i++) {
              globalState.container
                  .read(logsProvider.notifier)
                  .add(
                    Log.app(
                      '[$i]${utils.generateRandomString(maxLength: 200, minLength: 20)}',
                    ),
                  );
            }
          },
        ),
        if (system.isOhos)
          ListItem(
            title: const Text('导入二维码测试图到图库'),
            minVerticalPadding: 12,
            onTap: () {
              _importQrTestImage(context);
            },
          ),
        if (globalState.isPre)
          ListItem(
            title: Text(appLocalizations.crashTest),
            minVerticalPadding: 12,
            onTap: () async {
              final res = await globalState.showMessage(
                message: TextSpan(text: appLocalizations.confirmForceCrashCore),
              );
              if (res != true) {
                return;
              }
              coreController.crash();
            },
          ),
        ListItem(
          title: Text(appLocalizations.clearData),
          minVerticalPadding: 12,
          onTap: () async {
            final res = await globalState.showMessage(
              message: TextSpan(text: appLocalizations.confirmClearAllData),
            );
            if (res != true) {
              return;
            }
            await globalState.container
                .read(storeActionProvider.notifier)
                .handleClear();
          },
        ),
        // ListItem(
        //   title: Text(appLocalizations.loadTest),
        //   minVerticalPadding: 12,
        //   onTap: () {
        //     ref.read(loadingProvider.notifier).value = !ref.read(
        //       loadingProvider,
        //     );
        //   },
        // ),
        ListItem(
          title: Text(appLocalizations.pruneCache),
          minVerticalPadding: 12,
          onTap: () async {
            try {
              await globalState.container
                  .read(storeActionProvider.notifier)
                  .shakingStore();
              commonPrint.log('[developer-mode] prune cache success');
              if (context.mounted) {
                context.showNotifier('缓存修剪完成');
              }
            } catch (error, stackTrace) {
              commonPrint.log(
                '[developer-mode] prune cache error=$error stack=$stackTrace',
                logLevel: LogLevel.error,
              );
              if (context.mounted) {
                context.showNotifier('缓存修剪失败');
              }
            }
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, ref) {
    final appLocalizations = context.appLocalizations;
    final enable = ref.watch(
      appSettingProvider.select((state) => state.developerMode),
    );
    return BaseScaffold(
      title: appLocalizations.developerMode,
      body: SingleChildScrollView(
        padding: baseInfoEdgeInsets,
        child: Column(
          children: [
            CommonCard(
              type: CommonCardType.filled,
              radius: 18,
              child: ListItem.switchItem(
                padding: const EdgeInsets.only(left: 16, right: 16),
                title: Text(appLocalizations.developerMode),
                delegate: SwitchDelegate(
                  value: enable,
                  onChanged: (value) {
                    ref
                        .read(appSettingProvider.notifier)
                        .update(
                          (state) => state.copyWith(developerMode: value),
                        );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            _getDeveloperList(context, ref),
          ],
        ),
      ),
    );
  }
}
