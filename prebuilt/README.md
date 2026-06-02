# Prebuilt libcrypto artifacts

Place compiled `libcrypto` binaries here to skip the source compile step. The build hook looks up:

```
prebuilt/<version>/<os>-<arch>[-<iosSdk>]-<static|dynamic>/<libcrypto file>
```

Examples:

- `prebuilt/3.5.4/windows-x64-static/libcrypto_static.lib`
- `prebuilt/3.5.4/linux-x64-static/libcrypto.a`
- `prebuilt/3.5.4/android-arm64-static/libcrypto.a`
- `prebuilt/3.5.4/ios-arm64-iPhoneOS-static/libcrypto.a`

Generate artifacts with `dart run tool/build_prebuilts.dart` on each supported host, or from CI (see `.github/workflows/prebuilts.yml`).

When no prebuilt exists for a target triple, the hook compiles OpenSSL from source (if the host supports that target).
