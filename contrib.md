## Contributing and local builds

- Tooling: Dart 3.10+ / Flutter 3.38+ with Native Assets.
- **Git LFS** is required for `prebuilt/` binaries:
  ```bash
  git lfs install
  git clone --recurse-submodules https://github.com/advforks/openssl-dart.git
  cd openssl_dart
  git lfs pull
  dart run tool/verify_prebuilts.dart
  ```
- Clone with submodules: `git submodule update --init` if needed.
- Install deps: `dart pub get`.
- Regenerate libcrypto bindings:
  1. `dart run tool/ffigen.dart` (requires `openssl_repo/include` or extracted `openssl-3.5.4/include`)
  2. Optionally `dart run tool/trim_bindings.dart` (experimental: strips many libssl/TLS declarations; verify with `dart test` / `dart analyze`)
- Build native assets: `dart test` or `dart run example/main.dart` (uses LFS prebuilt when present, else compiles).
- Tests: `dart test`.
- Prebuilts: see [`prebuilt/README.md`](prebuilt/README.md). CI workflow `.github/workflows/prebuilts.yml` builds matrix artifacts.

### Publishing to pub.dev

`prebuilt/` is **excluded** from the published package (`.pubignore`). Pub consumers compile from source. To include prebuilts in a pub release, run `git lfs pull` first and adjust `.pubignore` deliberately.
