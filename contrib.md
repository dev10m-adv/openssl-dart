## Contributing and local builds

- Tooling: Dart 3.10+ / Flutter 3.38+ with Native Assets.
- **Git LFS** is required for `native/prebuilt/` binaries:
  ```bash
  git lfs install
  git clone --recurse-submodules https://github.com/advforks/openssl-dart.git
  cd openssl-dart
  git lfs pull
  dart run tool/verify_prebuilts.dart
  ```
- Clone with submodules: `git submodule update --init` (OpenSSL headers under `native/third_party/openssl`).
- Install deps: `dart pub get`.
- Regenerate libcrypto bindings:
  1. `dart run tool/ffigen.dart` (requires `native/third_party/openssl/include` or extracted sources)
  2. Optionally `dart run tool/trim_bindings.dart` (experimental: strips many libssl/TLS declarations; verify with `dart test` / `dart analyze`)
- Build native assets: `dart test` or `dart run example/main.dart` (uses LFS prebuilt when present, else compiles).
- Tests: `dart test`.
- Prebuilts: see [`native/prebuilt/README.md`](native/prebuilt/README.md). Hash-gated CI: `.github/workflows/prebuilts.yml` (runs when `native/**` or hook inputs change).
- Bump OpenSSL: see [CONTRIBUTING.md](CONTRIBUTING.md) checklist (`VERSION` → `dart run tool/sync_manifest.dart` → submodule tag).
- Build one triple: `TRIPLE=linux-x64 bash native/build/linux.sh` then `dart run tool/compute_build_hash.dart`.

### Publishing to pub.dev

`native/prebuilt/` is **excluded** from the published package (`.pubignore`). Pub consumers compile from source.
