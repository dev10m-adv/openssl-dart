## Contributing and local builds

- Tooling: Dart 3.10+ / Flutter 3.38+ with Native Assets.
- Clone with submodules: `git clone --recurse-submodules <repo>` (or `git submodule update --init`).
- Install deps: `dart pub get`.
- Regenerate libcrypto bindings:
  1. `dart run tool/ffigen.dart` (requires `openssl_repo/include` or extracted `openssl-3.5.4/include`)
  2. Optionally `dart run tool/trim_bindings.dart` (experimental: strips many libssl/TLS declarations; verify with `dart test` / `dart analyze`)
- Build native assets: `dart test` or `dart run example/main.dart` (first run compiles or uses prebuilt).
- Tests: `dart test`.
- Prebuilts: see [`prebuilt/README.md`](prebuilt/README.md) and `dart run tool/build_prebuilts.dart`.
