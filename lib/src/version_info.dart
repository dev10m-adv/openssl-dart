import 'third_party/openssl.g.dart' as bindings;

/// Runtime OpenSSL libcrypto version string (e.g. `3.5.4`).
String openSslLibcryptoVersion() {
  return '${bindings.OPENSSL_version_major()}.'
      '${bindings.OPENSSL_version_minor()}.'
      '${bindings.OPENSSL_version_patch()}';
}
