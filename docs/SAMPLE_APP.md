# Reference Flutter sample app

The **[openssltest](https://github.com/advforks/openssltest)** repository is the maintained **end-to-end sample** for importing `openssl` in a Flutter app.

It demonstrates:

- `pubspec.yaml` with a **git-pinned** dependency (and local path override for monorepo dev)
- One-command bootstrap: `dart run openssl:setup_prebuilts`
- Wrapper scripts: `scripts/bootstrap.ps1`, `scripts/flutter_run.ps1`, `scripts/flutter_build.ps1`
- Windows ARM64 CMake fix (`windows/cmake/community_vs.cmake`)
- VS Code / Cursor launch config with preLaunch bootstrap
- AES-256-CBC round-trip via `package:openssl/crypto.dart`
- Widget + unit tests

## Quick start (clone the sample)

```bash
git clone https://github.com/advforks/openssltest.git
cd openssltest
```

**Windows (PowerShell):**

```powershell
.\scripts\bootstrap.ps1
.\scripts\flutter_run.ps1 -d windows
```

**macOS / Linux:**

```bash
chmod +x scripts/bootstrap.sh scripts/flutter_run.sh
./scripts/bootstrap.sh
./scripts/flutter_run.sh -d macos   # or linux, android, ios
```

## Copy into your own app

Use this checklist — file templates live under [docs/templates/flutter/](templates/flutter/):

| Step | Action |
|------|--------|
| 1 | Add `openssl` to `pubspec.yaml` ([snippet](templates/flutter/pubspec.snippet.yaml)) |
| 2 | Copy `scripts/` from the sample or templates |
| 3 | Copy `windows/cmake/community_vs.cmake` (Windows on ARM hosts) |
| 4 | Copy `.vscode/settings.json` + optional `launch.json` / `tasks.json` |
| 5 | Run `dart run openssl:setup_prebuilts` after first `pub get` (git dep) |
| 6 | Import `package:openssl/crypto.dart` or raw `package:openssl/openssl.dart` |

See [FLUTTER.md](FLUTTER.md) for pub.dev vs git, platform triples, and CI verification.

## Minimal in-app example

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:openssl/crypto.dart';

void demo() {
  print('libcrypto ${openSslLibcryptoVersion()}');
  final key = Uint8List.fromList(utf8.encode('Nc92PMoPjcIls5QoXeki5yIPuhjjWMcx'));
  final iv = Uint8List.fromList(utf8.encode('1234567890123456'));
  final plain = Uint8List.fromList(utf8.encode('hello'));
  final enc = aes256Cbc(plain, key, iv, encrypt: true);
  final dec = aes256Cbc(enc, key, iv, encrypt: false);
  print(utf8.decode(dec)); // hello
}
```

The upstream repo also ships a smaller Flutter example at [example/flutter_openssl/](../example/flutter_openssl/) (path dependency, no platform folders).
