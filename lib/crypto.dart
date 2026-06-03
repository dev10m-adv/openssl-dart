/// Batteries-included libcrypto helpers for app teams.
///
/// Covers the most common needs without manual FFI:
/// - [aes256Cbc] — AES-256-CBC encrypt/decrypt
/// - [sha256], [sha512], [toHex] — digests
/// - [randomBytes] — CSPRNG
/// - [openSslLibcryptoVersion] — runtime version string
///
/// For the full C API use `package:openssl/openssl.dart`.
library;

export 'src/crypto/aes256_cbc.dart';
export 'src/crypto/digest.dart';
export 'src/crypto/random.dart';
export 'src/version_info.dart';
