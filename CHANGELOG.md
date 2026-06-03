## Unreleased

## 1.2.5

- `package:openssl/crypto.dart` gains `sha256`, `sha512`, `toHex`, and `randomBytes` so app teams avoid manual FFI for common operations.
- Sample app and `flutter_openssl` example showcase AES + SHA-256 + RAND.
- Fixed deprecated `Pointer.elementAt` in `aes256Cbc` (uses `+`).

## 1.2.4

- `package:openssl/crypto.dart`: `aes256Cbc`, `openSslLibcryptoVersion()` for app teams.
- [docs/SAMPLE_APP.md](docs/SAMPLE_APP.md) and expanded [docs/templates/flutter/](docs/templates/flutter/) (bootstrap scripts, VS Code, pubspec snippet).
- Upgraded [example/flutter_openssl/](example/flutter_openssl/) with AES demo.

## 1.2.3

- Flutter DX: [docs/FLUTTER.md](docs/FLUTTER.md), published `dart run openssl:setup_prebuilts` / `openssl:verify_prebuilts` (`bin/`), Windows ARM64 CMake template.
- Hook logs resolved prebuilt folder; clearer LFS pointer and compile-fallback messages.
- `lib/src/prebuilt_verify.dart` shared by `tool/` and `bin/` verify CLIs.

## 1.2.2

- Repo maintenance: strict prebuilt verify on PRs touching LFS paths, bot PRs for prebuilts/ffigen, Dependabot, LFS smoke, OpenSSL release checker, matrix health, stale prebuilt cleanup, release workflow.
- Tools: `sync_manifest.dart`, `check_submodule.dart`, `check_lfs_pointers.dart`, `check_repo.dart`; `verify_prebuilts --allow-partial`.
- Linux arm64 cross-compile in `native/build/linux.sh`.

## 1.2.1

- Version-first prebuilt layout: `native/prebuilt/<version>/<platform>/` with per-version `.build-hash`.
- Single OpenSSL pin: [`native/src/VERSION`](native/src/VERSION) drives Dart, scripts, and [`manifest.json`](native/prebuilt/manifest.json).

## 1.2.0

- Restructure native builds under `native/` (`build/`, `third_party/openssl`, `out/`, `prebuilt/`).
- Platform-centric prebuilt dirs (`linux-x64`, `windows-arm64`, `ios-xcframework`, etc.); dynamic-only LFS artifacts.
- Hash-gated prebuilts CI (`native/prebuilt/.build-hash`, `tool/compute_build_hash.dart`); skip matrix when inputs unchanged.
- iOS xcframework and macOS universal prebuilt resolution in the hook.

## 1.1.1

- Canonical git repository: [advforks/openssl-dart](https://github.com/advforks/openssl-dart) (non-fork; supports Git LFS prebuilts). The former `advforks/openssl_dart` fork remains read-only on GitHub.
- Track prebuilts with Git LFS; exclude from pub.dev (`.pubignore`).
- Hook ignores LFS pointer stubs; add `dart run tool/verify_prebuilts.dart`.
- Expand prebuilts CI matrix (Linux, macOS, Windows x64/ARM64).

## 1.1.0

- Scope package to **libcrypto only**: trimmed FFI bindings (no libssl/TLS symbols).
- Build hook compiles by **target OS** (fixes Android/iOS cross-build logic on Unix hosts).
- **Hybrid prebuilts**: copy from `prebuilt/<triple>/` when present, else compile from source.
- Improved Windows MSVC discovery via `vswhere` and multiple VS editions.
- Added `platforms:` in pubspec, Flutter example, expanded tests, and GitHub Actions CI.
- Analyzer excludes generated bindings file.

## 1.0.1 (2026-01-20)

- Add Android platform support.
- Add iOS platform support.

## 1.0.0 (2026-01-19)

- Initial version.
