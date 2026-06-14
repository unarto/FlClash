# HarmonyOS NEXT packaging notes

This repository now contains an `ohos/` host project and the minimum local plugin skeletons required to produce a signed HarmonyOS `.hap` artifact for migration work.

## Current status

- Branch: `feat/ohos-support`
- Added OpenHarmony host project under `ohos/`
- Added local plugin `ohos/` platform skeletons for:
  - `plugins/proxy`
  - `plugins/rust_api`
  - `plugins/wifi_ssid`
  - `plugins/window_ext`
  - `plugins/setup`
- Release HAP compilation and signing work with the OpenHarmony SDK's built-in demo signing materials when `OHOS_SDK_HOME` points to the OpenHarmony SDK root
- The Flutter runtime is not implemented on OHOS yet. This branch does not ship a working HarmonyOS app runtime, only host/package scaffolding.

## What is missing

The current branch does not provide a runnable HarmonyOS port yet:

- The Dart app runtime still lacks OHOS equivalents for the Android-only `app`, `service`, and `tile` channels
- No verified OHOS `FlClashCore` runtime artifact is bundled or launched by the host project
- Startup on OHOS is intentionally blocked with an explicit unsupported-runtime error instead of entering a broken half-ported path

## Hard prerequisites

This project is pinned to modern Flutter on the mainline, and the OpenHarmony Flutter toolchain is still published on separate branches/releases. Most published SDK combinations still do not line up cleanly with this repository's Dart and Flutter constraints, so a clean checkout should be expected to need toolchain validation before it builds.

Before building, install and verify:

1. DevEco Studio / OpenHarmony SDK with `hvigor`, `ohpm`, `hdc`
2. OpenHarmony Flutter SDK branch compatible with this project
3. A dependency set that provides `ohos` implementations for all required plugins
4. `OHOS_SDK_HOME` or `OHOS_BASE_SDK_HOME` must point to the OpenHarmony SDK root, for example:

```bash
export OHOS_SDK_HOME=/path/to/sdk/default/openharmony
export OHOS_BASE_SDK_HOME=$OHOS_SDK_HOME
```

## Verified toolchain findings

The following combinations were validated in this branch:

- `3.7.12-ohos-1.0.4`
  - Flutter/Dart toolchain starts, but `flutter pub get` fails immediately because it bundles Dart `2.19.6`
  - This repository requires Dart `>=3.8.0`
- `3.22.1-ohos-1.1.0` and `3.22.1-ohos-1.1.1`
  - `flutter --version --machine` reports a valid OpenHarmony Flutter version
  - Both bundle Dart `3.4.0`
  - This is still below the repository requirement `>=3.8.0`
- `oh-3.35.7-release`
  - Bundles Dart `3.9.2`, which is new enough for this repository
  - The published branch snapshot may still report Flutter version `0.0.0-unknown` during pub version solving on some setups
  - In this workspace, with a local `oh-3.35.7-release` checkout and OpenHarmony 6.0.2(22) SDK, the packaging scaffold produced a signed release HAP after the local hvigor wrapper prepared signing assets from the SDK-provided OpenHarmony demo keystore

## Recommended build path

1. Clone OpenHarmony Flutter SDK from the current upstream release source
2. Select a release that is both:
   - published with a valid Flutter semantic version
   - bundled with Dart `>=3.8.0`
3. Point Flutter to the Harmony SDK:

```bash
flutter config --enable-ohos
flutter config --ohos-sdk <OpenHarmony SDK path>
```

4. Regenerate the `ohos/` host if your chosen Flutter OHOS branch requires a newer template
5. Resolve third-party plugin compatibility for:
   - `path_provider`
   - `shared_preferences`
   - `url_launcher`
   - `image_picker`
   - `file_picker`
   - `device_info_plus`
   - `connectivity_plus`
   - `package_info_plus`
   - `app_links`
   - `mobile_scanner`
   - `dynamic_color`

## Build command

After a compatible Harmony toolchain is installed, build the packaging scaffold from the project root with the Harmony-enabled Flutter SDK:

```bash
dart setup.dart ohos
```

Or build directly in the host project:

```bash
cd ohos
hvigorw --mode module -p product=default -p module=entry assembleHap
```

The host build still emits the default hvigor artifact at:

```text
ohos/entry/build/default/outputs/default/entry-default-signed.hap
```

The release-style artifact copied by `setup.dart` is:

```text
dist/FlClash-<version>-ohos-arm64.hap
```

## Emulator install smoke test

Once the HAP has been built, verify packaging on a HarmonyOS emulator before treating it as a releasable artifact.

Prerequisites:

1. Start a HarmonyOS emulator or connect a test device
2. Ensure `hdc list targets` shows exactly one target, or set `HDC_TARGET=<target>`
3. Keep the generated HAP at `dist/FlClash-<version>-ohos-arm64.hap`

Run the repository smoke test:

```bash
bash scripts/ohos/install_and_launch.sh
```

Or pass an explicit artifact path:

```bash
bash scripts/ohos/install_and_launch.sh dist/FlClash-<version>-ohos-arm64.hap
```

What this verifies today:

- the signed HAP can be installed with `hdc install -r`
- the entry ability can be started with `aa start`
- the package is usable as an installable host scaffold on an emulator

What a passing result means on the current branch:

- install succeeds
- launch succeeds
- the app reaches the in-app unsupported-runtime error screen

This is intentionally weaker than a real product smoke test. The current branch still does **not** provide a working OHOS runtime, so the expected result is installable packaging plus a controlled startup failure, not functional proxy behavior.

During the build, `ohos/hvigor/hvigor-wrapper.js` prepares these generated signing assets under `ohos/hvigor/.signing/openharmony/`:

- `OpenHarmonyApplicationRelease.cer`
- `OpenHarmonyProfileRelease.json`
- `OpenHarmonyProfileRelease.p7b`

These files are generated from the SDK's built-in `OpenHarmony.p12` demo keystore and are ignored by git.
