#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-flclash-deb-builder:ubuntu20}"
ARCH="${1:-amd64}"

if [[ "${ARCH}" != "amd64" && "${ARCH}" != "arm64" ]]; then
  echo "unsupported arch: ${ARCH}, allowed: amd64|arm64"
  exit 1
fi

cd "${SCRIPT_DIR}"

# ---------- 0. init submodules on host (SSH keys available here) ----------
if [ -f .gitmodules ]; then
  echo "[0/3] initialising git submodules on host ..."
  git submodule update --init --recursive || \
    echo "  warn: host submodule init failed; will retry inside container via HTTPS"
fi

# ---------- 1. build docker image ----------
echo "[1/3] building docker image: ${IMAGE_NAME}"
docker build -f docker/ubuntu20-deb.Dockerfile -t "${IMAGE_NAME}" .

# ---------- 2. build deb inside container ----------
echo "[2/3] building deb package inside container (arch=${ARCH}) ..."
docker run --rm \
  -v "${SCRIPT_DIR}:/work" \
  -v flclash-pub-cache:/root/.pub-cache \
  -v flclash-go-mod:/root/go/pkg/mod \
  -v flclash-go-build:/root/.cache/go-build \
  -w /work \
  -e APPIMAGE_EXTRACT_AND_RUN=1 \
  "${IMAGE_NAME}" \
  bash -lc "
    set -euo pipefail

    # Ensure submodules are present (HTTPS rewrite is in image git config)
    git submodule update --init --recursive

    flutter pub get

    # Build all default targets (deb + appimage + rpm on amd64, deb on arm64).
    # Building inside Ubuntu 20.04 ensures bundled libs are ABI-compatible.
    dart setup.dart linux --arch ${ARCH} --env stable
  "

# ---------- 3. collect output ----------
echo "[3/3] copying packages to project root ..."
found=0
for ext in deb AppImage rpm; do
  if compgen -G "${SCRIPT_DIR}/dist/*.${ext}" > /dev/null; then
    cp -fv "${SCRIPT_DIR}"/dist/*.${ext} "${SCRIPT_DIR}/"
    found=1
  fi
done

if [ "${found}" -eq 1 ]; then
  echo ""
  echo "===== done ====="
  ls -lh "${SCRIPT_DIR}"/*.deb "${SCRIPT_DIR}"/*.AppImage "${SCRIPT_DIR}"/*.rpm 2>/dev/null || true
else
  echo "error: no packages found under dist/. Build may have failed."
  exit 2
fi
