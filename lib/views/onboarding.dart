import 'package:fl_clash/common/russia_preset.dart';
import 'package:fl_clash/controller.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OnboardingView extends ConsumerStatefulWidget {
  const OnboardingView({super.key});

  @override
  ConsumerState<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends ConsumerState<OnboardingView> {
  final PageController _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _nextPage() async {
    await _pageController.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _handlePasteLink() async {
    // В проекте используется singleton `appController`, а не Provider<AppController> в дереве.
    final controller = appController;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final url = data?.text?.trim();
    if (url != null && url.startsWith('http')) {
      await controller.addProfileFormURL(url);
    }
    if (!mounted) return;
    await _nextPage();
  }

  Widget _buildPrimaryButton({required String text, required VoidCallback? onPressed}) {
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        child: Text(text),
      ),
    );
  }

  Widget _buildSecondaryButton({required String text, required VoidCallback? onPressed}) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        child: Text(text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  const Text(
                    'Добро пожаловать в FlClashR',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Свободный доступ к интернету',
                    style: TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const Spacer(),
                  _buildPrimaryButton(
                    text: '📋 Вставить ссылку',
                    onPressed: _handlePasteLink,
                  ),
                  const SizedBox(height: 12),
                  _buildSecondaryButton(
                    text: 'Пропустить',
                    onPressed: () {
                      _nextPage();
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  const Text(
                    'Вы в России?',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '✅ YouTube и Telegram — через защищённый канал\n'
                    '✅ Банки и Госуслуги — напрямую\n'
                    '✅ Реклама — блокируется',
                    style: TextStyle(fontSize: 16),
                    textAlign: TextAlign.left,
                  ),
                  const Spacer(),
                  _buildPrimaryButton(
                    text: 'Да, я в России',
                    onPressed: () {
                      applyRussia2026Preset(ref);
                      _nextPage();
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildSecondaryButton(
                    text: 'Нет',
                    onPressed: () {
                      _nextPage();
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  const Text(
                    'Готово!',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Нажмите кнопку для подключения',
                    style: TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const Spacer(),
                  _buildPrimaryButton(
                    text: 'Начать',
                    onPressed: () {
                      ref
                          .read(appSettingProvider.notifier)
                          .update((state) => state.copyWith(disclaimerAccepted: true));
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
