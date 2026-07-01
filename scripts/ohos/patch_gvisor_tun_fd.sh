#!/usr/bin/env bash
# Patch the metacubex/gvisor fdbased endpoint so the gVisor TUN stack works
# inside the OHOS VpnExtension sandbox.
#
# gVisor's fdbased.New() calls isSocketFD(fd) -> unix.Fstat(fd) to decide
# between the recvmmsg (socket) and readv (tun) dispatchers. On OHOS the VPN
# tun fd cannot be Fstat'd (the musl/SELinux sandbox denies it), so endpoint
# setup fails with "unix.Fstat(..) failed: permission denied" and the gVisor
# stack never starts -- which silently breaks ALL TCP through the tunnel
# (UDP/DNS keeps working because it is injected straight into gVisor).
#
# The tun fd is never a socket, so on Fstat failure we fall back to the
# non-socket (readv) dispatch path instead of failing. This is applied to the
# module cache because gvisor is a normal (non-replaced) dependency.
#
# Idempotent. Usage: patch_gvisor_tun_fd.sh [go-executable]
set -euo pipefail

GO="${1:-go}"
MARKER="OHOS: VPN tun fd is not Fstat-able"

GOMODCACHE="$("$GO" env GOMODCACHE 2>/dev/null || true)"
if [ -z "${GOMODCACHE}" ]; then
  echo "[patch_gvisor] could not resolve GOMODCACHE via '$GO'; skipping" >&2
  exit 0
fi

shopt -s nullglob
endpoints=("$GOMODCACHE"/github.com/metacubex/gvisor@*/pkg/tcpip/link/fdbased/endpoint.go)
shopt -u nullglob

if [ ${#endpoints[@]} -eq 0 ]; then
  echo "[patch_gvisor] no metacubex/gvisor fdbased endpoint.go under ${GOMODCACHE}; skipping" >&2
  exit 0
fi

for ep in "${endpoints[@]}"; do
  if grep -q "${MARKER}" "$ep"; then
    echo "[patch_gvisor] already patched: $ep"
    continue
  fi
  if ! grep -q 'unix.Fstat(%v,...) failed' "$ep"; then
    echo "[patch_gvisor] unexpected content, no Fstat error to patch in $ep; skipping" >&2
    continue
  fi
  chmod u+w "$ep"
  python3 - "$ep" "$MARKER" <<'PY'
import sys
path, marker = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as f:
    src = f.read()
old = '\t\treturn false, fmt.Errorf("unix.Fstat(%v,...) failed: %v", fd, err)\n'
new = '\t\treturn false, nil // ' + marker + ' (musl/SELinux); treat as non-socket\n'
if old not in src:
    raise SystemExit("[patch_gvisor] could not find Fstat return line in " + path)
with open(path, "w", encoding="utf-8") as f:
    f.write(src.replace(old, new, 1))
PY
  echo "[patch_gvisor] patched: $ep"
done
