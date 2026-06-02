/// Headers and symbol rules for libcrypto-only FFI bindings (no libssl/TLS).
library;

/// Public OpenSSL headers that must not be parsed for libcrypto-only bindings.
const excludedHeaders = <String>{
  'dtls1.h',
  'prov_ssl.h',
  'quic.h',
  'srtp.h',
  'ssl2.h',
  'ssl3.h',
  'sslerr.h',
  'sslerr_legacy.h',
  'tls1.h',
};

/// Returns true when [fileName] is a libssl/TLS public header.
bool isExcludedHeader(String fileName) {
  final base = fileName.replaceAll(r'\', '/').split('/').last;
  return excludedHeaders.contains(base);
}

/// Returns true for libcrypto symbols; false for libssl/TLS and similar.
bool isLibcryptoSymbol(String name) {
  if (name.startsWith('SSL_') || name.startsWith('_SSL_')) return false;
  if (name.startsWith('DTLS_')) return false;
  if (name.startsWith('TLS_')) return false;
  if (name.startsWith('OSSL_QUIC')) return false;
  if (name.startsWith('ossl_quic')) return false;
  return true;
}

/// System / CRT symbols that sometimes leak in via platform includes.
bool isSystemLeakSymbol(String name) {
  const prefixes = [
    'imax',
    'strtoimax',
    'strtoumax',
    'wcstoimax',
    'wcstoumax',
    'pthread_',
    'clock_gettime',
    'clock_getres',
    'clock_settime',
    'waitid',
    'fd_set',
    'FD_',
    'timersub',
    'timeradd',
    'timespec',
  ];
  for (final prefix in prefixes) {
    if (name.startsWith(prefix)) return true;
  }
  return false;
}

bool includeBindingText(String text) {
  if (RegExp(
    r'\b(pthread_|clock_gettime|waitid|fd_set|P_ALL|P_PID|P_PGID|idtype_t|imaxdiv|div_t\b|\bdiv\(|getenv|ldiv_t|TLS_ST_|futimes|lutimes|timeval\b|rusage\b|nanosleep|gettimeofday)',
  ).hasMatch(text)) {
    return false;
  }
  return true;
}

bool includeDeclaration(String name) => isLibcryptoSymbol(name) && !isSystemLeakSymbol(name);
