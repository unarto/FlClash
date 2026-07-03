import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/pages/scan.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';

class AddProfileView extends StatelessWidget {
  final BuildContext context;

  const AddProfileView({super.key, required this.context});

  Future<void> _handleAddProfileFormFile() async {
    globalState.container
        .read(profilesActionProvider.notifier)
        .addProfileFormFile();
  }

  Future<void> _handleAddProfileFormURL(String url) async {
    commonPrint.log('[ohos-profile-url] AddProfileView submit url=$url');
    globalState.container
        .read(profilesActionProvider.notifier)
        .addProfileFormURL(url);
  }

  Future<void> _toScan() async {
    if (system.isDesktop) {
      globalState.container
          .read(profilesActionProvider.notifier)
          .addProfileFormQrCode();
      return;
    }
    final url = await BaseNavigator.push(context, const ScanPage());
    if (url != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleAddProfileFormURL(url);
      });
    }
  }

  Future<void> _toAdd() async {
    final appLocalizations = context.appLocalizations;
    final url = system.isOhos
        ? await BaseNavigator.push<String>(context, const _OhosUrlInputPage())
        : await globalState.showCommonDialog<String>(
            child: InputDialog(
              autovalidateMode: AutovalidateMode.onUnfocus,
              title: appLocalizations.importFromURL,
              labelText: appLocalizations.url,
              value: '',
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return appLocalizations.emptyTip('').trim();
                }
                if (!value.isUrl) {
                  return appLocalizations.urlTip('').trim();
                }
                return null;
              },
            ),
          );
    commonPrint.log(
      '[ohos-profile-url] AddProfileView dialog/page result=$url',
    );
    if (url != null) {
      _handleAddProfileFormURL(url);
    }
  }

  @override
  Widget build(context) {
    final appLocalizations = context.appLocalizations;
    return ListView(
      children: [
        ListItem(
          leading: const Icon(Icons.qr_code_sharp),
          title: Text(appLocalizations.qrcode),
          subtitle: Text(appLocalizations.qrcodeDesc),
          onTap: _toScan,
        ),
        ListItem(
          leading: const Icon(Icons.upload_file_sharp),
          title: Text(appLocalizations.file),
          subtitle: Text(appLocalizations.fileDesc),
          onTap: _handleAddProfileFormFile,
        ),
        ListItem(
          leading: const Icon(Icons.cloud_download_sharp),
          title: Text(appLocalizations.url),
          subtitle: Text(appLocalizations.urlDesc),
          onTap: _toAdd,
        ),
      ],
    );
  }
}

class URLFormDialog extends StatefulWidget {
  const URLFormDialog({super.key});

  @override
  State<URLFormDialog> createState() => _URLFormDialogState();
}

class _URLFormDialogState extends State<URLFormDialog> {
  final _urlController = TextEditingController();

  Future<void> _handleAddProfileFormURL() async {
    final url = _urlController.value.text;
    if (url.isEmpty) return;
    Navigator.of(context).pop<String>(url);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return CommonDialog(
      title: appLocalizations.importFromURL,
      actions: [
        TextButton(
          onPressed: _handleAddProfileFormURL,
          child: Text(appLocalizations.submit),
        ),
      ],
      child: SizedBox(
        width: 300,
        child: Wrap(
          runSpacing: 16,
          children: [
            TextField(
              keyboardType: TextInputType.url,
              minLines: 1,
              maxLines: 5,
              onSubmitted: (_) {
                _handleAddProfileFormURL();
              },
              onEditingComplete: _handleAddProfileFormURL,
              controller: _urlController,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: appLocalizations.url,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OhosUrlInputPage extends StatefulWidget {
  const _OhosUrlInputPage();

  @override
  State<_OhosUrlInputPage> createState() => _OhosUrlInputPageState();
}

class _OhosUrlInputPageState extends State<_OhosUrlInputPage> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  Future<void> _pasteFromClipboard({bool submit = false}) async {
    final text = (await app?.getClipboardText())?.trim() ?? '';
    commonPrint.log(
      '[ohos-profile-url] paste from clipboard length=${text.length}',
    );
    if (text.isEmpty) {
      if (mounted) {
        context.showNotifier('剪贴板为空');
      }
      return;
    }
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _formKey.currentState?.validate();
    if (submit) {
      await _handleSubmit();
    }
  }

  String? _validateUrl(BuildContext context, [String? value]) {
    final appLocalizations = context.appLocalizations;
    final url = (value ?? _controller.text).trim();
    if (url.isEmpty) {
      return appLocalizations.emptyTip('').trim();
    }
    if (!url.isUrl) {
      return appLocalizations.urlTip('').trim();
    }
    return null;
  }

  Future<void> _handleSubmit() async {
    commonPrint.log('[ohos-profile-url] page submit tapped');
    final validationMessage = _validateUrl(context);
    if (validationMessage != null) {
      _formKey.currentState?.validate();
      commonPrint.log(
        '[ohos-profile-url] page submit validation failed '
        'url=${_controller.text} message=$validationMessage',
      );
      return;
    }
    final url = _controller.text.trim();
    commonPrint.log('[ohos-profile-url] page submit pop url=$url');
    Navigator.of(context).pop<String>(url);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return CommonScaffold(
      title: appLocalizations.importFromURL,
      resizeToAvoidBottomInset: true,
      actions: [
        IconButton(onPressed: _handleSubmit, icon: const Icon(Icons.check)),
      ],
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _controller,
                keyboardType: TextInputType.url,
                autofocus: true,
                textInputAction: TextInputAction.done,
                minLines: 1,
                maxLines: 5,
                onFieldSubmitted: (_) {
                  _handleSubmit();
                },
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: appLocalizations.url,
                ),
                validator: (value) => _validateUrl(context, value),
              ),
              const SizedBox(height: 16),
              Text(
                'HarmonyOS 当前请手动输入订阅 URL。',
                style: context.textTheme.bodyMedium?.toLight,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pasteFromClipboard,
                    icon: const Icon(Icons.content_paste),
                    label: const Text('粘贴'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      _pasteFromClipboard(submit: true);
                    },
                    icon: const Icon(Icons.playlist_add_check),
                    label: const Text('粘贴并提交'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _handleSubmit,
                child: Text(appLocalizations.submit),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
