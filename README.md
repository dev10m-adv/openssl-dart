> Minimum Dart SDK 3.10 (Flutter 3.38+) with Native Assets/hooks support.

[![pub.dev](https://img.shields.io/pub/v/openssl.svg)](https://pub.dev/packages/openssl)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

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

### Flutter notes

- Requires **Flutter 3.38+** (Dart 3.10+ native assets).
- Android: install NDK via Android Studio when building from source.
- iOS: macOS host + Xcode when building from source.
- If another plugin embeds OpenSSL, prefer one crypto stack to avoid duplicate symbols with static linking.

## Using the bindings

```dart
import 'package:openssl/openssl.dart' as openssl;
```

See [`example/main.dart`](example/main.dart) for AES-256-CBC. Follow OpenSSL docs for `OPENSSL_free`, `EVP_*_free`, etc.

## Prebuilt binaries

Shipped under [`prebuilt/`](prebuilt/README.md) when available:

```
prebuilt/3.5.4/<os>-<arch>[-<iosSdk>]-<static|dynamic>/libcrypto.*
```

Missing triples fall back to compiling OpenSSL from source. Populate prebuilts with CI or `dart run tool/build_prebuilts.dart` (see [`contrib.md`](contrib.md)).

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
