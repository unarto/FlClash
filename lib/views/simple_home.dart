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
  static const _backgroundColor = Color(0xFFF6F6F6);
  static const _importColor = Color(0xFF4A90D9);
  static const _powerOnColor = Color(0xFF2E7D32);
  static const _powerOffColor = Color(0xFF9E9E9E);
  static const _russiaColor = Color(0xFFD32F2F);
  static const _settingsColor = Color(0xFF6750A4);

  Future<void> _showImportDialog() async {
    final ctx = context;
    final controller = TextEditingController();
    final shouldImport = await showDialog<bool>(
      context: ctx,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          title: const Text('Импорт ключа'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'https://...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            maxLines: 2,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Импортировать'),
            ),
          ],
        );
      },
    );
    final url = controller.text.trim();
    controller.dispose();
    if (shouldImport != true || url.isEmpty) return;
    if (!ctx.mounted) return;
    await appController.addProfileFormURL(url.trim());
  }

  void _toggleConnection(bool isStart) {
    appController.updateStatus(!isStart, isInit: !ref.read(initProvider));
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
    final isStart = ref.watch(isStartProvider);
    final runTime = ref.watch(runTimeProvider);
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final powerSubtitle = isStart
        ? (runTime != null ? utils.getTimeText(runTime) : 'Подключено')
        : 'VPN выключен';

    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FlClashRP',
                style: textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Свободный интернет',
                style: textTheme.bodyLarge?.copyWith(
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isStart
                      ? const Color(0xFFE8F5E9)
                      : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  isStart ? '● Подключено' : '● Отключено',
                  style: textTheme.bodyMedium?.copyWith(
                    color: isStart ? _powerOnColor : Colors.grey.shade700,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.95,
                  children: [
                    _HomeCard(
                      icon: Icons.download_rounded,
                      iconColor: _importColor,
                      iconBackgroundColor: _importColor.withOpacity(0.12),
                      title: 'Импорт ключа',
                      subtitle: 'Добавить VPN',
                      onTap: _showImportDialog,
                    ),
                    _HomeCard(
                      icon: Icons.power_settings_new_rounded,
                      iconColor: isStart ? _powerOnColor : _powerOffColor,
                      iconBackgroundColor: (isStart ? _powerOnColor : _powerOffColor)
                          .withOpacity(0.12),
                      title: isStart ? 'Выключить' : 'Включить',
                      subtitle: powerSubtitle,
                      onTap: () => _toggleConnection(isStart),
                    ),
                    _HomeCard(
                      icon: Icons.public_rounded,
                      iconColor: _russiaColor,
                      iconBackgroundColor: _russiaColor.withOpacity(0.12),
                      title: 'Россия, вперёд!',
                      subtitle: 'Применить настройки',
                      onTap: _applyRussiaPreset,
                    ),
                    _HomeCard(
                      icon: Icons.tune_rounded,
                      iconColor: _settingsColor,
                      iconBackgroundColor: _settingsColor.withOpacity(0.12),
                      title: 'Настройки',
                      subtitle: 'Конфигурация',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const ToolsView()),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16, top: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      'from pavel with love ♥',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.black.withOpacity(0.35),
                        letterSpacing: 1.2,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
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
  final Color iconColor;
  final Color iconBackgroundColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HomeCard({
    required this.icon,
    required this.iconColor,
    required this.iconBackgroundColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: Colors.white,
      elevation: 1,
      surfaceTintColor: Colors.black12,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: iconBackgroundColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 28, color: iconColor),
              ),
              const Spacer(),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
