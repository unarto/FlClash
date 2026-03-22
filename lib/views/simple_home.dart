import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/russia_preset.dart';
import 'package:fl_clash/controller.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SimpleHomeView extends ConsumerStatefulWidget {
  const SimpleHomeView({super.key});

  @override
  ConsumerState<SimpleHomeView> createState() => _SimpleHomeViewState();
}

class _SimpleHomeViewState extends ConsumerState<SimpleHomeView> {
  static const _accentColor = Color(0xFFFF6D00);
  static const _backgroundColor = Color(0xFF111214);
  static const _cardRadius = 24.0;
  static const _onlineIndicatorColor = Colors.greenAccent;
  static const _offlineIndicatorColor = Colors.grey;
  static const _activePowerEndColor = Color(0xFFFF8F3D);
  static const _titleStyle = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w800,
    color: Colors.white,
  );
  static const _cardTitleStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w800,
    color: Colors.white,
  );
  static const _sectionSpacing = SizedBox(height: 24);

  Future<void> _showImportDialog() async {
    final controller = TextEditingController();

    try {
      final shouldImport = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Импорт ключа'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Вставьте ссылку',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Импортировать'),
              ),
            ],
          );
        },
      );
      final url = controller.text.trim();
      if (shouldImport != true || url.isEmpty) {
        return;
      }
      await appController.addProfileFormURL(url);
    } finally {
      controller.dispose();
    }
  }

  Future<void> _openTools() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ToolsView()),
    );
  }

  Future<void> _toggleConnection(bool isStarted) async {
    await appController.updateStatus(
      !isStarted,
      isInit: !ref.read(initProvider),
    );
  }

  Future<void> _applyRussiaPreset() async {
    applyRussia2026Preset(ref);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Настройки для России применены ✅')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isStarted = ref.watch(isStartProvider);
    final runTime = ref.watch(runTimeProvider);
    final profileCount = ref.watch(
      profilesProvider.select((state) => state.length),
    );
    final statusText = isStarted ? 'Подключено' : 'Отключено';
    final statusColor = isStarted ? _onlineIndicatorColor : Colors.grey.shade400;
    final powerSubtitle = isStarted
        ? (runTime != null
            ? 'Работает: ${utils.getTimeText(runTime)}'
            : 'Подключено')
        : 'Сейчас отключено';
    final importSubtitle = profileCount > 0
        ? 'Профилей: $profileCount'
        : 'Вставьте ссылку на подписку';

    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('FlClashRP', style: _titleStyle),
              const SizedBox(height: 6),
              Text(
                'Свободный интернет',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade400),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: isStarted
                          ? _onlineIndicatorColor
                          : _offlineIndicatorColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              _sectionSpacing,
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1,
                  children: [
                    _HomeCard(
                      icon: Icons.download_rounded,
                      title: '📥 Импорт ключа',
                      subtitle: importSubtitle,
                      startColor: Colors.blue.shade700,
                      endColor: Colors.blue.shade500,
                      onTap: _showImportDialog,
                    ),
                    _HomeCard(
                      icon: Icons.power_settings_new,
                      title: '⚡ Вкл / Выкл',
                      subtitle: powerSubtitle,
                      startColor: isStarted ? _accentColor : Colors.grey.shade700,
                      endColor: isStarted
                          ? _activePowerEndColor
                          : Colors.grey.shade600,
                      onTap: () => _toggleConnection(isStarted),
                    ),
                    _HomeCard(
                      icon: Icons.flag_rounded,
                      title: '🇷🇺 Россия,\nвперёд!',
                      subtitle: 'Применить готовые настройки',
                      startColor: Colors.red.shade700,
                      endColor: Colors.red.shade500,
                      onTap: _applyRussiaPreset,
                    ),
                    _HomeCard(
                      icon: Icons.settings_rounded,
                      title: '⚙️ Настройки',
                      subtitle: 'Открыть инструменты',
                      startColor: Colors.grey.shade700,
                      endColor: Colors.grey.shade600,
                      onTap: _openTools,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color startColor;
  final Color endColor;
  final Future<void> Function() onTap;

  const _HomeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.startColor,
    required this.endColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(_SimpleHomeViewState._cardRadius);
    return Material(
      color: Colors.transparent,
      elevation: 4,
      borderRadius: borderRadius,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [startColor, endColor],
          ),
        ),
        child: InkWell(
          borderRadius: borderRadius,
          onTap: () async {
            await onTap();
          },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 40, color: Colors.white),
                const Spacer(),
                Text(title, style: _SimpleHomeViewState._cardTitleStyle),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.86),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
