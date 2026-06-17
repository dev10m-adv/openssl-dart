# Native prebuilt production workflow

## Strategy (hybrid)

| Layer | Role |
|-------|------|
| **Local bootstrap** (`dart run openssl:bootstrap_native --all`) | Builds every triple the **current host** can compile. Fast feedback for daily dev. |
| **CI prebuilts** (`.github/workflows/prebuilts.yml`) | Authoritative matrix: builds **all** platforms on the right OS runners. |
| **Git / path dependency** | Prebuilts live under `native/prebuilt/<version>/<triple>/` in the resolved openssl package (pub cache or monorepo). Never committed as blobs in app repos. |

Dev machines bootstrap locally; CI fills gaps (iOS, macOS, Linux) that Windows cannot build.

## What each host builds locally

| Host | Built by bootstrap | Skipped (use CI) |
|------|-------------------|------------------|
| **Windows x64** | `windows-x64`, `android-arm64-v8a`, `android-x86_64`* | `windows-arm64`, iOS, macOS, Linux |
| **Windows ARM64** | `windows-arm64`, `windows-x64`†, Android* | iOS, macOS, Linux |
| **macOS** | macOS, iOS, Linux, Android* | Windows |
| **Linux** | Linux, Android* | Windows, iOS, macOS |

\* Android requires NDK installed (`ANDROID_NDK_ROOT` or Android Studio SDK).  
† Cross-compile may fail on some setups; CI remains fallback.

## Developer workflow (Windows + Flutter)

### Prerequisites

1. Visual Studio 2022 with **Desktop development with C++**
2. **Android Studio** → SDK Manager → **NDK** installed
3. **Git for Windows** (bash + make for Android builds)

### One-time / after openssl upgrade

From app root (`secmail10`):

```powershell
./scripts/flutter_run.ps1   # natives only — does NOT start the app
```

Or:

```powershell
dart run openssl:bootstrap_native --all --skip-lfs
```

### Run the app

```powershell
./scripts/run_app.ps1 -d windows
# or
flutter run -d android
```

## CI/CD workflow

1. **openssl-dart** `prebuilts.yml` runs on push to `native/**` or hook changes.
2. Matrix builds all triples on ubuntu / macos / windows runners.
3. Artifacts merge into `native/prebuilt/<version>/` (LFS or release upload — team choice).
4. **App CI** (`secmail10`):
   - `flutter pub get`
   - `dart run openssl:bootstrap_native --all --skip-lfs` (optional cache; ensures host triples exist)
   - `flutter build windows` / `flutter build apk`

Pin openssl git `ref:` to a tag that matches CI-built prebuilts when using git dependencies.

## Commands

| Command | Purpose |
|---------|---------|
| `dart run openssl:bootstrap_native --all` | Build all local triples + log skips |
| `dart run openssl:bootstrap_native --triple windows-x64` | Single triple |
| `dart run openssl:setup_prebuilts` | Git LFS pull (when LFS blobs exist) |
| `dart run openssl:verify_prebuilts` | Checksum verify |

Set `OPENSSL_SKIP_NATIVE_HOOK=1` when running openssl tooling to avoid hook compile during `pub get`.

## Output layout

```
native/prebuilt/3.5.4/
  windows-x64/libcrypto-3-x64.dll
  android-arm64-v8a/libcrypto.so
  android-x86_64/libcrypto.so
  ...
native/out/bootstrap-report.txt   # last bootstrap summary
```
