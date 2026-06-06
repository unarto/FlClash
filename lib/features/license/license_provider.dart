// FlClash-BD — Riverpod license provider
//
// Drop into: lib/features/license/license_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'license_models.dart';
import 'license_service.dart';

/// Single instance of the service (cheap, just holds a Dio).
final licenseServiceProvider = Provider<LicenseService>((_) => LicenseService());

/// Async-loaded current license state from disk.
final licenseStateProvider =
    AsyncNotifierProvider<LicenseStateNotifier, LicenseState>(
  LicenseStateNotifier.new,
);

class LicenseStateNotifier extends AsyncNotifier<LicenseState> {
  @override
  Future<LicenseState> build() async {
    final svc = ref.read(licenseServiceProvider);
    return svc.load();
  }

  Future<void> activate(String code) async {
    final svc = ref.read(licenseServiceProvider);
    state = const AsyncLoading();
    try {
      final next = await svc.activate(code);
      state = AsyncData(next);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> revalidateIfNeeded() async {
    final svc = ref.read(licenseServiceProvider);
    final cur = state.valueOrNull;
    if (cur == null || !cur.isActivated) return;
    if (!cur.shouldRevalidateOnline) return;
    try {
      final next = await svc.revalidate(cur);
      state = AsyncData(next);
    } catch (_) {
      // network errors are tolerated until offline grace expires
    }
  }

  Future<void> clear() async {
    final svc = ref.read(licenseServiceProvider);
    await svc.clear();
    state = const AsyncData(LicenseState());
  }
}

/// Convenience: can the user start the tunnel right now?
///
///   true  -> proceed with normal updateStatus(true)
///   false -> show the activation screen instead
final canStartTunnelProvider = Provider<bool>((ref) {
  final s = ref.watch(licenseStateProvider).valueOrNull;
  if (s == null || !s.isActivated) return false;
  if (s.isExpired) return false;
  // we still allow start while offline, as long as we're inside grace
  if (s.lastOnlineCheck == null) return false;
  return s.isWithinOfflineGrace || s.shouldRevalidateOnline == false;
});
