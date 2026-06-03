import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../third_party/openssl.g.dart' as openssl;

/// Returns [length] cryptographically secure random bytes from libcrypto's `RAND_bytes`.
Uint8List randomBytes(int length) {
  if (length < 0) {
    throw ArgumentError.value(length, 'length', 'must be non-negative');
  }
  if (length == 0) {
    return Uint8List(0);
  }
  return using((arena) {
    final buf = arena.allocate<Uint8>(length);
    if (openssl.RAND_bytes(buf.cast<UnsignedChar>(), length) != 1) {
      throw StateError('OpenSSL RAND_bytes failed');
    }
    return Uint8List.fromList(buf.asTypedList(length));
  });
}
