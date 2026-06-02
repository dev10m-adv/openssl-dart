## 1.1.0

- Scope package to **libcrypto only**: trimmed FFI bindings (no libssl/TLS symbols).
- Build hook compiles by **target OS** (fixes Android/iOS cross-build logic on Unix hosts).
- **Hybrid prebuilts**: copy from `prebuilt/<triple>/` when present, else compile from source.
- Improved Windows MSVC discovery via `vswhere` and multiple VS editions.
- Added `platforms:` in pubspec, Flutter example, expanded tests, and GitHub Actions CI.
- Analyzer excludes generated bindings file.

## 1.0.1 (2026-01-20)

- Add Android platform support.
- Add iOS platform support.

## 1.0.0 (2026-01-19)

- Initial version.
