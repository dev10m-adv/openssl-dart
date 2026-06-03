> Minimum Dart SDK 3.10 (Flutter 3.38+) with Native Assets/hooks support.

[![pub.dev](https://img.shields.io/pub/v/openssl.svg)](https://pub.dev/packages/openssl)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Git (with prebuilts):** clone [github.com/advforks/openssl-dart](https://github.com/advforks/openssl-dart) and run `git lfs pull` (see [`native/prebuilt/README.md`](native/prebuilt/README.md)).

This package ships **OpenSSL 3.5.4 libcrypto** (no libssl/TLS) for Dart and Flutter via FFI and Native Assets. Bindings mirror the libcrypto C API; you manage memory and lifetimes using the [OpenSSL documentation](https://docs.openssl.org/).

Background on hooks/native assets: [Dart build hooks: create Dart packages from C libs](https://medium.com/@lucazzp/dart-build-hooks-create-dart-packages-from-c-libs-10cbb9360a69).

## What you get

- libcrypto C API in Dart (`EVP_*`, `RSA_*`, `X509_*`, `PEM_*`, providers, etc.)
- Generated bindings may still list libssl/TLS symbol names; only **libcrypto** is linked (see `no-ssl` in the build hook). Do not call `SSL_*` APIs.
- Native Assets hook: uses **prebuilt** `libcrypto` when available, otherwise compiles from source
- No Dart wrappers; full control over allocation and cleanup

## Supported platforms

| Target | Notes |
|--------|--------|
| Windows x64/ARM | Host must be Windows with MSVC 2022+ (or prebuilt) |
| Linux x64/ARM | Host Linux/macOS, or prebuilt |
| macOS arm64/x64 | Host macOS, or prebuilt |
| Android arm/x64 | Host Linux/macOS + NDK, or prebuilt |
| iOS device/simulator | Host macOS + Xcode, or prebuilt |
| **Web** | Not supported (FFI + native assets) |

## Getting started (Dart or Flutter)

1. Add the dependency:

   ```yaml
   dependencies:
     openssl: ^1.1.0
   ```

2. Run your app or tests once. The hook links `libcrypto` (prebuilt if present, otherwise ~1 minute compile).

   **Flutter apps:** [docs/FLUTTER.md](docs/FLUTTER.md) · **Sample app:** [docs/SAMPLE_APP.md](docs/SAMPLE_APP.md) · helpers: `package:openssl/crypto.dart`

### Flutter notes

- Requires **Flutter 3.38+** (Dart 3.10+ native assets). See **[docs/FLUTTER.md](docs/FLUTTER.md)** for git vs pub.dev, LFS setup, and platform selection.
- After adding a **git** dependency: `dart run openssl:setup_prebuilts` (materializes LFS prebuilts).
- Android: install NDK via Android Studio when building from source.
- iOS: macOS host + Xcode when building from source.
- If another plugin embeds OpenSSL, prefer one crypto stack to avoid duplicate symbols with static linking.

### Git dependency (prebuilts)

```yaml
dependencies:
  openssl:
    git:
      url: https://github.com/advforks/openssl-dart.git
      ref: v1.2.3   # pin a tag or commit
```

```bash
GIT_LFS_SKIP_SMUDGE=1 flutter pub get   # if LFS smudge fails during checkout
dart run openssl:setup_prebuilts
flutter run
```

## Using the bindings

Convenience helpers (no manual FFI) — `package:openssl/crypto.dart`:

```dart
import 'dart:typed_data';
import 'package:openssl/crypto.dart';

openSslLibcryptoVersion();                 // "3.5.4"
toHex(sha256(bytes));                       // SHA-256 hex
randomBytes(16);                            // CSPRNG
aes256Cbc(plain, key, iv, encrypt: true);   // AES-256-CBC
```

Full C API — `package:openssl/openssl.dart`:

```dart
import 'package:openssl/openssl.dart' as openssl;
```

See [`example/main.dart`](example/main.dart) and [`docs/FLUTTER.md`](docs/FLUTTER.md). Follow OpenSSL docs for `OPENSSL_free`, `EVP_*_free`, etc.

## Prebuilt binaries (git clones only)

Shipped under [`native/prebuilt/`](native/prebuilt/README.md) via **Git LFS** (`git lfs pull`). Not included on pub.dev. CI skips rebuilds when `native/prebuilt/<version>/.build-hash` matches native build inputs (version from [`native/src/VERSION`](native/src/VERSION)).

```
native/prebuilt/3.5.4/<platform-dir>/libcrypto.*
```

Examples: `windows-arm64/`, `linux-x64/`, `ios-xcframework/`. Missing triples compile from source. See [`contrib.md`](contrib.md) and `dart run tool/build_prebuilts.dart`.

## Toolchain matrix (compile from source)

| Target | Host Windows | Host macOS | Host Linux |
|--------|--------------|------------|------------|
| Windows | Yes (MSVC) | Prebuilt only | Prebuilt only |
| Linux | Prebuilt only | Yes | Yes |
| macOS | Prebuilt only | Yes | Prebuilt only |
| Android | Prebuilt only | Yes (NDK) | Yes (NDK) |
| iOS | Prebuilt only | Yes (Xcode) | Prebuilt only |

## Build notes

- Configure uses `no-ssl` (libcrypto only).
- Unix targets enable assembly optimizations; Windows builds use `no-asm` for toolchain compatibility.
- Regenerate bindings: `git submodule update --init` then `dart run tool/ffigen.dart` and `dart run tool/trim_bindings.dart`.

## Contributing

See [`contrib.md`](contrib.md).
