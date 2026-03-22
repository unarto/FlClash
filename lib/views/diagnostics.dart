import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DiagnosticsView extends ConsumerStatefulWidget {
  const DiagnosticsView({super.key});

  @override
  ConsumerState<DiagnosticsView> createState() => _DiagnosticsViewState();
}

enum _CheckStatus { idle, checking, ok, fail }

class _ServiceCheck {
  final String key;
  final String name;
  final String url;

  const _ServiceCheck({
    required this.key,
    required this.name,
    required this.url,
  });
}

class _DiagnosticsViewState extends ConsumerState<DiagnosticsView> {
  static const _services = [
    _ServiceCheck(key: 'internet', name: '🌐 Интернет', url: 'https://www.google.com'),
    _ServiceCheck(key: 'youtube', name: '▶️ YouTube', url: 'https://www.youtube.com'),
    _ServiceCheck(key: 'telegram', name: '💬 Telegram', url: 'https://telegram.org'),
    _ServiceCheck(key: 'gemini', name: '🤖 Gemini', url: 'https://gemini.google.com'),
    _ServiceCheck(key: 'banks', name: '🏦 Банки', url: 'https://www.sberbank.ru'),
  ];

  late final Map<String, _CheckStatus> _statuses = {
    for (final service in _services) service.key: _CheckStatus.idle,
  };

  bool _isChecking = false;
  String? _ipInfoText;
  String? _ipInfoError;

  Future<void> _runChecks() async {
    if (_isChecking) return;

    setState(() {
      _isChecking = true;
      _ipInfoText = null;
      _ipInfoError = null;
      for (final service in _services) {
        _statuses[service.key] = _CheckStatus.checking;
      }
    });

    final results = await Future.wait(
      _services.map((service) => _checkService(service.url)),
    );

    if (!mounted) return;

    setState(() {
      for (var i = 0; i < _services.length; i++) {
        _statuses[_services[i].key] = results[i] ? _CheckStatus.ok : _CheckStatus.fail;
      }
      _isChecking = false;
    });

    final ipInfoResult = await _fetchIpInfo();
    if (!mounted) return;

    setState(() {
      _ipInfoText = ipInfoResult.text;
      _ipInfoError = ipInfoResult.error;
    });
  }

  Future<bool> _checkService(String url) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl('HEAD', Uri.parse(url)).timeout(
            const Duration(seconds: 5),
          );
      request.followRedirects = true;
      final response = await request.close().timeout(const Duration(seconds: 5));
      return response.statusCode >= 200 && response.statusCode < 400;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<_IpInfoResult> _fetchIpInfo() async {
    final client = HttpClient();
    try {
      final request = await client
          .getUrl(Uri.parse('https://ipinfo.io/json'))
          .timeout(const Duration(seconds: 5));
      final response = await request.close().timeout(const Duration(seconds: 5));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const _IpInfoResult(error: 'Не удалось получить IP-данные. Попробуйте позже.');
      }
      final body = await utf8.decodeStream(response).timeout(
            const Duration(seconds: 5),
          );
      final data = jsonDecode(body);
      if (data is! Map<String, dynamic>) {
        return const _IpInfoResult(error: 'Сервис IP-данных вернул неожиданный ответ.');
      }
      final ip = data['ip']?.toString();
      final country = data['country']?.toString();
      if (ip == null || ip.isEmpty) {
        return const _IpInfoResult(error: 'IP-адрес не найден в ответе сервиса.');
      }
      return _IpInfoResult(
        text: country != null && country.isNotEmpty ? 'Ваш IP: $ip ($country)' : 'Ваш IP: $ip',
      );
    } on SocketException {
      return const _IpInfoResult(error: 'Не удалось подключиться к ipinfo.io.');
    } on HttpException {
      return const _IpInfoResult(error: 'Сервис IP-данных временно недоступен.');
    } on FormatException {
      return const _IpInfoResult(error: 'Не удалось разобрать ответ сервиса IP-данных.');
    } catch (_) {
      return const _IpInfoResult(error: 'Ошибка при получении информации об IP.');
    } finally {
      client.close(force: true);
    }
  }

  Widget _buildStatusIcon(_CheckStatus status) {
    switch (status) {
      case _CheckStatus.ok:
        return const Icon(Icons.check_circle, color: Colors.green);
      case _CheckStatus.fail:
        return const Icon(Icons.cancel, color: Colors.red);
      case _CheckStatus.checking:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case _CheckStatus.idle:
        return const Icon(Icons.radio_button_unchecked, color: Colors.grey);
    }
  }

  String _buildSubtitle(_CheckStatus status) {
    switch (status) {
      case _CheckStatus.ok:
        return 'Доступен';
      case _CheckStatus.fail:
        return 'Недоступен';
      case _CheckStatus.checking:
        return 'Проверяем...';
      case _CheckStatus.idle:
        return 'Нажмите «Проверить»';
    }
  }

  String? _buildAdvice() {
    if (_isChecking || _statuses.values.any((status) => status == _CheckStatus.checking)) {
      return null;
    }

    final statuses = _statuses;
    final allFailed = statuses.values.every((status) => status == _CheckStatus.fail);
    if (allFailed) {
      return 'Проверьте интернет-соединение';
    }

    final geminiFailed = statuses['gemini'] == _CheckStatus.fail;
    final banksFailed = statuses['banks'] == _CheckStatus.fail;

    final othersExceptGemini = _services
        .where((service) => service.key != 'gemini')
        .every((service) => statuses[service.key] == _CheckStatus.ok);
    if (geminiFailed && othersExceptGemini) {
      return 'Смените сервер на Европу или США';
    }

    final othersExceptBanks = _services
        .where((service) => service.key != 'banks')
        .every((service) => statuses[service.key] == _CheckStatus.ok);
    if (banksFailed && othersExceptBanks) {
      return 'Отключите VPN для российских сайтов';
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final advice = _buildAdvice();

    return CommonScaffold(
      title: 'Проверить доступ',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: _isChecking ? null : _runChecks,
              child: Text(_isChecking ? 'Проверяем...' : 'Проверить'),
            ),
          ),
          for (final service in _services) ...[
            ListItem(
              leading: _buildStatusIcon(_statuses[service.key] ?? _CheckStatus.idle),
              title: Text(service.name),
              subtitle: Text(
                _buildSubtitle(_statuses[service.key] ?? _CheckStatus.idle),
              ),
            ),
            service != _services.last ? const Divider(height: 0) : const SizedBox.shrink(),
          ],
          if (_ipInfoText != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(_ipInfoText!),
            ),
          if (_ipInfoError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                _ipInfoError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (advice != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                advice,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}

class _IpInfoResult {
  final String? text;
  final String? error;

  const _IpInfoResult({this.text, this.error});
}
