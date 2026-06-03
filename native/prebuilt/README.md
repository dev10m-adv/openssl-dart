# Prebuilt libcrypto artifacts

Versioned LFS binaries under `native/prebuilt/<version>/` (see [`native/src/VERSION`](../src/VERSION) and [`manifest.json`](manifest.json)).

| Path | Artifact |
|------|----------|
| `3.5.4/android-arm64-v8a/` | `libcrypto.so` |
| `3.5.4/windows-arm64/` | `libcrypto-3-arm64.dll` |
| `3.5.4/ios-xcframework/` | `OpenSSL.xcframework` |
| … | (see manifest) |

## Layout

Artifacts live only under `native/prebuilt/<version>/<triple>/`. Flat paths like `native/prebuilt/windows-arm64/` are rejected by `verify_prebuilts.dart`.

## Integrity

Each version directory includes `manifest.json` (per-artifact SHA-256) and optionally `manifest.json.sig` (Ed25519 over the manifest). Downstream apps should pin a git tag and verify before release — see [docs/DOWNSTREAM_VERIFICATION.md](../../docs/DOWNSTREAM_VERIFICATION.md).

Optional strict verification at build time: `OPENSSL_VERIFY_PREBUILTS=1`.

## Git LFS

```bash
git lfs install
git clone --recurse-submodules https://github.com/advforks/openssl-dart.git
cd openssl-dart
git lfs pull
dart run tool/verify_prebuilts.dart
```

## OpenSSL version bump

1. Edit [`native/src/VERSION`](../src/VERSION) (single source of truth).
2. Run `dart run tool/sign_prebuilts.dart` (updates manifests and index `activeVersion`).
3. Point `native/third_party/openssl` submodule at the new tag.
4. CI builds `native/prebuilt/<new-version>/…` (new `.build-hash` per version).
5. Optionally delete the old version directory to trim LFS.

Recompute hash: `dart run tool/compute_build_hash.dart` (writes `native/prebuilt/<version>/.build-hash`).

## pub.dev

`native/prebuilt/` is in [`.pubignore`](../../.pubignore). Pub consumers compile on first `pub get`.
