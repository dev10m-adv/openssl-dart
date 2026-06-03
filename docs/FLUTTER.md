# Using openssl in Flutter apps

Integration guide for **pub.dev** and **GitHub**. For a full working app, start with the **[openssltest sample](SAMPLE_APP.md)**.

Requires **Flutter 3.38+** (Dart 3.10+ native assets). **Web** is not supported.

## Quick start (5 minutes)

1. Add the dependency (git recommended for fast LFS prebuilts):

```yaml
dependencies:
  ffi: ^2.1.5
  openssl:
    git:
      url: https://github.com/advforks/openssl-dart.git
      ref: v1.2.5
```

2. Bootstrap (from your app root):

```bash
export GIT_LFS_SKIP_SMUDGE=1          # PowerShell: $env:GIT_LFS_SKIP_SMUDGE = "1"
flutter pub get
dart run openssl:setup_prebuilts
flutter run -d <device>
```

3. Call libcrypto:

```dart
import 'package:openssl/crypto.dart';        // helpers (no manual FFI)
import 'package:openssl/openssl.dart' as ssl; // full C API

void demo() {
  print(openSslLibcryptoVersion());          // "3.5.4"
  final digest = toHex(sha256(bytes));        // SHA-256 hex
  final nonce = randomBytes(16);              // CSPRNG
  final enc = aes256Cbc(plain, key, iv, encrypt: true);
}
```

`package:openssl/crypto.dart` exports: `aes256Cbc`, `sha256`, `sha512`, `toHex`,
`randomBytes`, `openSslLibcryptoVersion`. For anything else, use the raw C API.

## pub.dev vs git

| Source | Prebuilt LFS binaries | First build |
|--------|----------------------|-------------|
| **pub.dev** `openssl: ^1.2.5` | No — compiles from source | ~1 min per platform |
| **git** + `setup_prebuilts` | Yes (when LFS pulled) | Seconds |

Pin git `ref:` to a **tag or commit**, not a floating branch.

## Copy-paste checklist for new apps

Templates: [docs/templates/flutter/](templates/flutter/). Reference implementation: **[openssltest](SAMPLE_APP.md)**.

```
your_app/
├── pubspec.yaml              # openssl git or pub.dev dep
├── scripts/
│   ├── bootstrap.ps1         # from templates
│   ├── bootstrap.sh
│   ├── flutter_run.ps1
│   └── flutter_build.ps1
├── windows/cmake/
│   └── community_vs.cmake    # Windows on ARM64 only
└── .vscode/
    ├── settings.json         # GIT_LFS_SKIP_SMUDGE + CMAKE_TOOLCHAIN_FILE
    ├── launch.json           # optional: preLaunch bootstrap
    └── tasks.json
```

## Automatic native binary selection

You never pass a platform triple. `flutter run -d <device>` supplies the target to the build hook:

| Flutter target | Prebuilt folder (git + LFS) |
|----------------|----------------------------|
| Android arm64 device | `android-arm64-v8a/` |
| Android x86_64 emulator | `android-x86_64/` |
| iOS device / simulator | `ios-xcframework/` |
| macOS | `macos-universal/` |
| Windows x64 / ARM64 | `windows-x64/` / `windows-arm64/` |
| Linux x64 / arm64 | `linux-x64/` / `linux-arm64/` |

Missing prebuilts compile from source when the host toolchain allows (see README toolchain matrix).

## CLI commands (run from your app directory)

| Command | Purpose |
|---------|---------|
| `dart run openssl:setup_prebuilts` | `git lfs pull` + verify (git dep) |
| `dart run openssl:verify_prebuilts` | Verify prebuilts in a clone |

## Git LFS troubleshooting

If `flutter pub get` fails on LFS smudge:

```bash
GIT_LFS_SKIP_SMUDGE=1 flutter pub get
dart run openssl:setup_prebuilts
```

## Windows on ARM64 (CMake)

If both VS **Community** and **Build Tools** are installed, set before building:

```powershell
$env:CMAKE_TOOLCHAIN_FILE = "$PWD/windows/cmake/community_vs.cmake"
```

Copy [templates/flutter/windows/cmake/community_vs.cmake](templates/flutter/windows/cmake/community_vs.cmake) into your app.

## CI (optional)

```bash
export OPENSSL_VERIFY_PREBUILTS=1
flutter build apk
```

See [DOWNSTREAM_VERIFICATION.md](DOWNSTREAM_VERIFICATION.md).

## FFI notes

- Use `arena.allocate<Int>(1)` for OpenSSL `int *outl` parameters.
- Cast byte buffers with `.cast<UnsignedChar>()` from `dart:ffi`.
- Follow OpenSSL docs for `OPENSSL_free`, `EVP_*_free`, etc.

## Duplicate OpenSSL

Avoid embedding a second OpenSSL via another plugin when using static linking.

## More examples

- Dart CLI: [example/main.dart](../example/main.dart)
- Minimal Flutter: [example/flutter_openssl/](../example/flutter_openssl/)
- Full Flutter sample: [openssltest](SAMPLE_APP.md)
