import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:openssl/openssl.dart' as openssl;

Uint8List aes(Uint8List input, Uint8List key, Uint8List iv, {required bool encrypt}) {
  if (key.length != 32) {
    throw ArgumentError.value(key.length, 'key', 'Key must be 32 bytes for AES-256-CBC');
  }
  if (iv.length != 16) {
    throw ArgumentError.value(iv.length, 'iv', 'IV must be 16 bytes for AES-256-CBC');
  }

  return using((arena) {
    final ctx = openssl.EVP_CIPHER_CTX_new();
    if (ctx == nullptr) throw StateError('Failed to create EVP_CIPHER_CTX');

    final inPtr = arena.allocate<Uint8>(input.isEmpty ? 1 : input.length);
    final keyPtr = arena.allocate<Uint8>(key.length);
    final ivPtr = arena.allocate<Uint8>(iv.length);
    final outPtr = arena.allocate<Uint8>(input.length + openssl.EVP_MAX_BLOCK_LENGTH);
    final outLenPtr = arena.allocate<Int>(2);

    try {
      inPtr.asTypedList(input.length).setAll(0, input);
      keyPtr.asTypedList(key.length).setAll(0, key);
      ivPtr.asTypedList(iv.length).setAll(0, iv);

      final initResult = encrypt
          ? openssl.EVP_EncryptInit_ex(
              ctx,
              openssl.EVP_aes_256_cbc(),
              nullptr,
              keyPtr.cast<UnsignedChar>(),
              ivPtr.cast<UnsignedChar>(),
            )
          : openssl.EVP_DecryptInit_ex(
              ctx,
              openssl.EVP_aes_256_cbc(),
              nullptr,
              keyPtr.cast<UnsignedChar>(),
              ivPtr.cast<UnsignedChar>(),
            );
      _checkResult(initResult, 'init');

      final updateResult = encrypt
          ? openssl.EVP_EncryptUpdate(
              ctx,
              outPtr.cast<UnsignedChar>(),
              outLenPtr,
              inPtr.cast<UnsignedChar>(),
              input.length,
            )
          : openssl.EVP_DecryptUpdate(
              ctx,
              outPtr.cast<UnsignedChar>(),
              outLenPtr,
              inPtr.cast<UnsignedChar>(),
              input.length,
            );
      _checkResult(updateResult, 'update');

      var outLen = outLenPtr.value;
      final finalResult = encrypt
          ? openssl.EVP_EncryptFinal_ex(ctx, outPtr.elementAt(outLen).cast<UnsignedChar>(), outLenPtr)
          : openssl.EVP_DecryptFinal_ex(ctx, outPtr.elementAt(outLen).cast<UnsignedChar>(), outLenPtr);
      _checkResult(finalResult, 'final');

      outLen += outLenPtr.value;
      return Uint8List.fromList(outPtr.asTypedList(outLen));
    } finally {
      openssl.EVP_CIPHER_CTX_free(ctx);
    }
  });
}

void _checkResult(int result, String step) {
  if (result != 1) throw StateError('OpenSSL AES $step failed');
}

void main() {
  final key = utf8.encode('Nc92PMoPjcIls5QoXeki5yIPuhjjWMcx');
  final iv = utf8.encode('1234567890123456');
  const message = 'Secret message for AES-256-CBC';
  final plaintext = utf8.encode(message);

  final encrypted = aes(plaintext, Uint8List.fromList(key), Uint8List.fromList(iv), encrypt: true);
  final decrypted = aes(encrypted, Uint8List.fromList(key), Uint8List.fromList(iv), encrypt: false);

  print('cipher (b64): ${base64.encode(encrypted)}');
  print('roundtrip: ${utf8.decode(decrypted)}');
}
