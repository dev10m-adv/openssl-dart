import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../third_party/openssl.g.dart' as openssl;

/// Computes the SHA-256 digest (32 bytes) of [data] using libcrypto.
Uint8List sha256(Uint8List data) => _digest(data, openssl.EVP_sha256());

/// Computes the SHA-512 digest (64 bytes) of [data] using libcrypto.
Uint8List sha512(Uint8List data) => _digest(data, openssl.EVP_sha512());

Uint8List _digest(Uint8List data, Pointer<openssl.evp_md_st> md) {
  if (md == nullptr) {
    throw StateError('Digest algorithm unavailable');
  }
  return using((arena) {
    final ctx = openssl.EVP_MD_CTX_new();
    if (ctx == nullptr) {
      throw StateError('Failed to create EVP_MD_CTX');
    }
    try {
      final inPtr = arena.allocate<Uint8>(data.isEmpty ? 1 : data.length);
      if (data.isNotEmpty) {
        inPtr.asTypedList(data.length).setAll(0, data);
      }
      final size = openssl.EVP_MD_get_size(md);
      final outPtr = arena.allocate<Uint8>(size);
      final outLenPtr = arena.allocate<UnsignedInt>(1);

      if (openssl.EVP_DigestInit_ex(ctx, md, nullptr) != 1) {
        throw StateError('OpenSSL digest init failed');
      }
      if (openssl.EVP_DigestUpdate(ctx, inPtr.cast(), data.length) != 1) {
        throw StateError('OpenSSL digest update failed');
      }
      if (openssl.EVP_DigestFinal_ex(ctx, outPtr.cast<UnsignedChar>(), outLenPtr) != 1) {
        throw StateError('OpenSSL digest final failed');
      }
      return Uint8List.fromList(outPtr.asTypedList(outLenPtr.value));
    } finally {
      openssl.EVP_MD_CTX_free(ctx);
    }
  });
}

/// Lowercase hex encoding of [bytes] (e.g. for digests).
String toHex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
