// FlClash-BD — Activation screen
//
// Drop into: lib/views/license/activation_screen.dart
//
// Routed to from the Start button when canStartTunnelProvider == false.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fl_clash/features/license/license_models.dart';
import 'package:fl_clash/features/license/license_provider.dart';
import 'package:fl_clash/features/license/license_service.dart';

class ActivationScreen extends ConsumerStatefulWidget {
  const ActivationScreen({super.key});

  @override
  ConsumerState<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends ConsumerState<ActivationScreen> {
  final _codeController = TextEditingController();
  String? _errorText;
  bool _busy = false;
  List<LicenseTier> _tiers = const [];

  @override
  void initState() {
    super.initState();
    _loadPricing();
  }

  Future<void> _loadPricing() async {
    final tiers = await ref.read(licenseServiceProvider).fetchPricing();
    if (mounted) setState(() => _tiers = tiers);
  }

  String _errorMessage(LicenseError e) {
    switch (e) {
      case LicenseError.invalidCode:
        return 'Invalid activation code.';
      case LicenseError.codeRevoked:
        return 'This code has been revoked. Contact support.';
      case LicenseError.codeExpired:
        return 'This subscription has expired. Please renew.';
      case LicenseError.deviceLimitReached:
        return 'Device limit reached for this code.';
      case LicenseError.deviceMismatch:
        return 'This code is bound to a different device.';
      case LicenseError.network:
        return 'No internet connection. Please try again.';
      case LicenseError.unknown:
        return 'Activation failed. Please try again.';
    }
  }

  Future<void> _submit() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _errorText = 'Enter your activation code');
      return;
    }
    setState(() {
      _busy = true;
      _errorText = null;
    });
    try {
      await ref.read(licenseStateProvider.notifier).activate(code);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on LicenseError catch (e) {
      setState(() => _errorText = _errorMessage(e));
    } catch (_) {
      setState(() => _errorText = 'Activation failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Activate Subscription')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Enter your activation code',
                  style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'You can buy a code from the seller. Each code activates the '
                'tunnel for the chosen duration on this device.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'Activation code',
                  hintText: 'BD-30D-XXXX-XXXX-XXXX',
                  errorText: _errorText,
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Activate'),
              ),
              const SizedBox(height: 32),
              if (_tiers.isNotEmpty) ...[
                Text('Plans', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                ..._tiers.map((t) => Card(
                      child: ListTile(
                        title: Text(t.label),
                        subtitle: Text(
                            '${t.maxDevices} device${t.maxDevices > 1 ? "s" : ""} • ${t.durationDays} days'),
                        trailing: Text('৳${t.priceBdt}',
                            style: theme.textTheme.titleMedium),
                      ),
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }
}
