// FlClash-BD — License service (calls the backend)
//
// Uses package:dio which is already a FlClash dependency.

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:math';

import 'license_models.dart';

class LicenseService {
  /// Set this to your deployed backend URL. Override at build time via:
  ///   --dart-define=LICENSE_BASE_URL=https://api.example.com
  static const String baseUrl = String.fromEnvironment(
    'LICENSE_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  static const String _prefsKey = 'flclash_bd_license_state';
  static const String _deviceIdKey = 'flclash_bd_device_id';

  final Dio _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  Future<String> deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null) return existing;
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    final id = base64Url.encode(bytes).replaceAll('=', '');
    await prefs.setString(_deviceIdKey, id);
    return id;
  }

  String _platformId() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  Future<LicenseState> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return const LicenseState();
    try {
      return LicenseState.fromJson(json.decode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const LicenseState();
    }
  }

  Future<void> save(LicenseState s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, json.encode(s.toJson()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  /// Activate a code on this device. Returns the new LicenseState on success
  /// or throws a [LicenseError].
  Future<LicenseState> activate(String code) async {
    final did = await deviceId();
    try {
      final r = await _dio.post('/v1/license/activate', data: {
        'code': code.trim(),
        'deviceId': did,
        'platform': _platformId(),
      });
      final data = r.data as Map<String, dynamic>;
      final state = LicenseState(
        token: data['token'] as String,
        code: code.trim(),
        tier: data['tier'] as String,
        expiresAt: DateTime.parse(data['expiresAt'] as String).toUtc(),
        lastOnlineCheck: DateTime.now().toUtc(),
        offlineGraceHours: (data['offlineGraceHours'] as int?) ?? 72,
        reValidateEveryHours: (data['reValidateAfter'] as int?) ?? 24,
      );
      await save(state);
      return state;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// Re-validate the cached token online. Returns updated state, or throws.
  Future<LicenseState> revalidate(LicenseState current) async {
    if (current.token == null) throw LicenseError.invalidCode;
    final did = await deviceId();
    try {
      final r = await _dio.post('/v1/license/validate', data: {
        'token': current.token,
        'deviceId': did,
      });
      final data = r.data as Map<String, dynamic>;
      final updated = current.copyWith(
        expiresAt: data['expiresAt'] != null
            ? DateTime.parse(data['expiresAt'] as String).toUtc()
            : current.expiresAt,
        lastOnlineCheck: DateTime.now().toUtc(),
      );
      await save(updated);
      return updated;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<List<LicenseTier>> fetchPricing() async {
    try {
      final r = await _dio.get('/v1/public/pricing');
      final tiers = (r.data['tiers'] as List).cast<Map<String, dynamic>>();
      return tiers.map(LicenseTier.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  LicenseError _mapError(DioException e) {
    final msg = (e.response?.data is Map &&
            (e.response!.data as Map)['error'] is String)
        ? (e.response!.data as Map)['error'] as String
        : '';
    switch (msg) {
      case 'invalid_code':
        return LicenseError.invalidCode;
      case 'code_revoked':
      case 'revoked':
        return LicenseError.codeRevoked;
      case 'code_expired':
      case 'expired':
        return LicenseError.codeExpired;
      case 'device_limit_reached':
        return LicenseError.deviceLimitReached;
      case 'device_mismatch':
        return LicenseError.deviceMismatch;
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.connectionError) {
      return LicenseError.network;
    }
    return LicenseError.unknown;
  }
}
