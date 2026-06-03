# Verifying prebuilt libcrypto (downstream Flutter apps)

The `openssl` package ships **prebuilt libcrypto only in git clones** (Git LFS under `native/prebuilt/<version>/`). **pub.dev** consumers compile from source and do not receive these binaries.

## What to trust

1. **Git ref** — Pin a tag or commit on [advforks/openssl-dart](https://github.com/advforks/openssl-dart), not a floating branch.
2. **Version manifest** — `native/prebuilt/<version>/manifest.json` lists each artifact path with **SHA-256** and size.
3. **Optional signature** — `native/prebuilt/<version>/manifest.json.sig` (Ed25519 over the manifest bytes), verifiable with [`native/src/prebuilt_signing_public.key`](../native/src/prebuilt_signing_public.key).

## Verify checksums (recommended minimum)

After `git lfs pull` or `dart run openssl:setup_prebuilts`, for each artifact you use:

```bash
VERSION=$(cat native/src/VERSION)   # in the openssl package root under .pub-cache or path dep
MANIFEST=native/prebuilt/$VERSION/manifest.json
# Example: windows-arm64 DLL
FILE=native/prebuilt/$VERSION/windows-arm64/libcrypto-3-arm64.dll
EXPECTED=$(jq -r '.artifacts["windows-arm64/libcrypto-3-arm64.dll"].sha256' "$MANIFEST")
ACTUAL=$(sha256sum "$FILE" | awk '{print $1}')
test "$EXPECTED" = "$ACTUAL"
```

In Dart (e.g. your app CI):

```dart
import 'package:crypto/crypto.dart';
import 'dart:io';

bool verifySha256(File file, String expectedHex) {
  final digest = sha256.convert(file.readAsBytesSync());
  return digest.toString() == expectedHex.toLowerCase();
}
```

Paths in `artifacts` are **relative to** `native/prebuilt/<version>/`.

## Verify manifest signature (provenance)

Fingerprint the public key once and pin it in your org config:

```bash
sha256sum native/src/prebuilt_signing_public.key
```

Then verify in CI using the same logic as `dart run tool/verify_prebuilts.dart` or call:

```bash
cd path/to/openssl_dart
dart run tool/verify_prebuilts.dart
```

## Optional: strict hook in your app build

When depending on a **git** copy of `openssl` (path or git dependency), enable at build time:

```bash
export OPENSSL_VERIFY_PREBUILTS=1
flutter build apk
```

The package hook will **fail closed** if checksums (and signature, when present) do not match. Default is warn-only when a manifest exists.

## What this does not provide

- **Apple / Microsoft store code signing** — use your own release signing pipelines.
- **Protection if an attacker can change manifest, binaries, and public key in one commit** — pin the public key fingerprint out-of-band.
- **pub.dev path dependencies** — no LFS prebuilts in the published package.
