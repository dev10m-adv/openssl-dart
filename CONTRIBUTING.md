# Contributing

## Tooling

- Dart 3.10+ / Flutter 3.38+ with Native Assets
- Git LFS for `native/prebuilt/`

```bash
git lfs install
git clone --recurse-submodules https://github.com/advforks/openssl-dart.git
cd openssl-dart
git lfs pull
dart pub get
```

## Repository health

```bash
dart run tool/check_repo.dart          # strict (full prebuilt matrix)
dart run tool/check_repo.dart --allow-partial
dart run tool/sign_prebuilts.dart      # version manifest + SHA-256; signs if PREBUILT_SIGNING_PRIVATE_KEY set
dart run tool/compute_build_hash.dart
```

Downstream apps that depend on git/LFS prebuilts should pin a release tag and verify checksums (and optionally the Ed25519 manifest signature). See [docs/DOWNSTREAM_VERIFICATION.md](docs/DOWNSTREAM_VERIFICATION.md).

### Prebuilt signing (maintainers)

1. Generate a keypair once: `dart run tool/generate_signing_keypair.dart` — commit `native/src/prebuilt_signing_public.key`, store the printed private key as GitHub secret `PREBUILT_SIGNING_PRIVATE_KEY`.
2. Prebuilts CI runs `dart run tool/sign_prebuilts.dart` with that secret to write `native/prebuilt/<version>/manifest.json` and `manifest.json.sig`.

## OpenSSL version bump checklist

1. Edit [`native/src/VERSION`](native/src/VERSION) (single source of truth).
2. `dart run tool/sign_prebuilts.dart` (updates version manifest + [`native/prebuilt/manifest.json`](native/prebuilt/manifest.json) index).
3. Point submodule at tag `openssl-<version>`:
   ```bash
   cd native/third_party/openssl
   git fetch --tags && git checkout openssl-<version>
   cd ../../..
   dart run tool/check_submodule.dart
   ```
4. Regenerate bindings if headers changed: `dart run tool/ffigen.dart` (CI opens a PR on submodule/ffigen changes).
5. Run [Prebuilts workflow](.github/workflows/prebuilts.yml) or build locally via `native/build/*.sh`; merge the bot PR with LFS artifacts.
6. Optionally remove `native/prebuilt/<old-version>/` (monthly [stale-prebuilts](.github/workflows/stale-prebuilts.yml) workflow may propose this).

## CI overview

| Workflow | Purpose |
|----------|---------|
| [ci.yml](.github/workflows/ci.yml) | analyze/test; strict prebuilt verify when PR touches LFS paths |
| [prebuilts.yml](.github/workflows/prebuilts.yml) | hash-gated matrix; opens PR (no direct push) |
| [matrix-health.yml](.github/workflows/matrix-health.yml) | weekly build smoke per triple |
| [security-openssl.yml](.github/workflows/security-openssl.yml) | weekly issue if newer OpenSSL release exists |

See also [`contrib.md`](contrib.md).
