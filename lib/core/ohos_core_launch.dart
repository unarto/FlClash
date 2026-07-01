enum OhosCoreLaunchMode { none, child, bundled, embedded }

class OhosCoreLaunch {
  final OhosCoreLaunchMode mode;
  final int? pid;

  const OhosCoreLaunch._({required this.mode, required this.pid});

  const OhosCoreLaunch.none()
    : this._(mode: OhosCoreLaunchMode.none, pid: null);

  const OhosCoreLaunch.child({required int pid})
    : this._(mode: OhosCoreLaunchMode.child, pid: pid);

  const OhosCoreLaunch.bundled({required int pid})
    : this._(mode: OhosCoreLaunchMode.bundled, pid: pid);

  const OhosCoreLaunch.embedded()
    : this._(mode: OhosCoreLaunchMode.embedded, pid: null);

  bool get hasTrackedCore => mode != OhosCoreLaunchMode.none;

  bool get canStopExternally =>
      mode == OhosCoreLaunchMode.child || mode == OhosCoreLaunchMode.bundled;
}

OhosCoreLaunch resolveOhosCoreLaunchAfterStopAttempt(
  OhosCoreLaunch launch, {
  required bool stopped,
}) {
  if (stopped) {
    return const OhosCoreLaunch.none();
  }
  return launch;
}
