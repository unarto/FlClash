// FlClash-BD — License client models
//
// Drop this folder into the FlClash fork at:
//   lib/features/license/
//
// License is GPL v3 (inherited from upstream FlClash).

class LicenseTier {
  final String id;
  final String label;
  final int durationDays;
  final int priceBdt;
  final int maxDevices;

  const LicenseTier({
    required this.id,
    required this.label,
    required this.durationDays,
    required this.priceBdt,
    required this.maxDevices,
  });

  factory LicenseTier.fromJson(Map<String, dynamic> j) => LicenseTier(
        id: j['id'] as String,
        label: j['label'] as String,
        durationDays: j['durationDays'] as int,
        priceBdt: j['priceBdt'] as int,
        maxDevices: j['maxDevices'] as int,
      );
}

class LicenseState {
  /// JWT issued by backend on successful activation.
  final String? token;

  /// The human-readable code the user redeemed, e.g. "BD-30D-XXXX-XXXX-XXXX".
  final String? code;

  /// Tier id, e.g. "TIER_30D".
  final String? tier;

  /// When the subscription expires (UTC). Null => never activated.
  final DateTime? expiresAt;

  /// Last time we successfully validated online.
  final DateTime? lastOnlineCheck;

  /// Offline grace window before we refuse to start.
  final int offlineGraceHours;

  /// How often to re-validate online while online.
  final int reValidateEveryHours;

  const LicenseState({
    this.token,
    this.code,
    this.tier,
    this.expiresAt,
    this.lastOnlineCheck,
    this.offlineGraceHours = 72,
    this.reValidateEveryHours = 24,
  });

  bool get isActivated => token != null && code != null && expiresAt != null;

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now().toUtc());

  /// Whether the local cache is still trustworthy without an online check.
  bool get isWithinOfflineGrace {
    if (lastOnlineCheck == null) return false;
    final ageHours =
        DateTime.now().toUtc().difference(lastOnlineCheck!).inHours;
    return ageHours <= offlineGraceHours;
  }

  /// Whether the client should hit the backend again now.
  bool get shouldRevalidateOnline {
    if (lastOnlineCheck == null) return true;
    final ageHours =
        DateTime.now().toUtc().difference(lastOnlineCheck!).inHours;
    return ageHours >= reValidateEveryHours;
  }

  LicenseState copyWith({
    String? token,
    String? code,
    String? tier,
    DateTime? expiresAt,
    DateTime? lastOnlineCheck,
    int? offlineGraceHours,
    int? reValidateEveryHours,
  }) {
    return LicenseState(
      token: token ?? this.token,
      code: code ?? this.code,
      tier: tier ?? this.tier,
      expiresAt: expiresAt ?? this.expiresAt,
      lastOnlineCheck: lastOnlineCheck ?? this.lastOnlineCheck,
      offlineGraceHours: offlineGraceHours ?? this.offlineGraceHours,
      reValidateEveryHours: reValidateEveryHours ?? this.reValidateEveryHours,
    );
  }

  Map<String, dynamic> toJson() => {
        'token': token,
        'code': code,
        'tier': tier,
        'expiresAt': expiresAt?.toIso8601String(),
        'lastOnlineCheck': lastOnlineCheck?.toIso8601String(),
        'offlineGraceHours': offlineGraceHours,
        'reValidateEveryHours': reValidateEveryHours,
      };

  factory LicenseState.fromJson(Map<String, dynamic> j) => LicenseState(
        token: j['token'] as String?,
        code: j['code'] as String?,
        tier: j['tier'] as String?,
        expiresAt: j['expiresAt'] != null
            ? DateTime.parse(j['expiresAt'] as String)
            : null,
        lastOnlineCheck: j['lastOnlineCheck'] != null
            ? DateTime.parse(j['lastOnlineCheck'] as String)
            : null,
        offlineGraceHours: (j['offlineGraceHours'] as int?) ?? 72,
        reValidateEveryHours: (j['reValidateEveryHours'] as int?) ?? 24,
      );
}

enum LicenseError {
  invalidCode,
  codeRevoked,
  codeExpired,
  deviceLimitReached,
  deviceMismatch,
  network,
  unknown,
}
