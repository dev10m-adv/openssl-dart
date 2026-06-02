import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:openssl/openssl.dart' as openssl;
import 'package:test/test.dart';

void main() {
  group('OpenSSL libcrypto', () {
    test('reports OpenSSL 3.5.4', () {
      final version =
          '${openssl.OPENSSL_version_major()}.${openssl.OPENSSL_version_minor()}.${openssl.OPENSSL_version_patch()}';
      expect(version, equals('3.5.4'));
    });

    group('AES-256-CBC', () {
      test('encrypt/decrypt roundtrip', () {
        final key = utf8.encode('Nc92PMoPjcIls5QoXeki5yIPuhjjWMcx');
        final iv = utf8.encode('1234567890123456');
        const message = 'Secret message for AES-256-CBC';
        final plaintext = utf8.encode(message);

        final ciphertext = aes(plaintext, key, iv, encrypt: true);
        expect(ciphertext, isNot(equals(plaintext)));

        final decrypted = aes(ciphertext, key, iv, encrypt: false);
        expect(utf8.decode(decrypted), equals(message));
      });

      test('rejects invalid key length', () {
        expect(
          () => aes(Uint8List.fromList([1]), Uint8List.fromList([1, 2, 3]), Uint8List(16), encrypt: true),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    test('SHA-256 digest of hello', () {
      const expected = '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824';
      using((arena) {
        final ctx = openssl.EVP_MD_CTX_new();
        expect(ctx, isNot(nullptr));
        final md = openssl.EVP_sha256();
        final input = utf8.encode('hello');
        final inPtr = arena.allocate<Uint8>(input.length);
        inPtr.asTypedList(input.length).setAll(0, input);
        final outPtr = arena.allocate<Uint8>(openssl.EVP_MD_get_size(md));
        final outLen = arena.allocate<UnsignedInt>(1);
        try {
          expect(openssl.EVP_DigestInit_ex(ctx, md, nullptr), 1);
          expect(
            openssl.EVP_DigestUpdate(ctx, inPtr.cast(), input.length),
            1,
          );
          expect(openssl.EVP_DigestFinal_ex(ctx, outPtr.cast<UnsignedChar>(), outLen), 1);
          final hex = outPtr
              .asTypedList(outLen.value)
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join();
          expect(hex, equals(expected));
        } finally {
          openssl.EVP_MD_CTX_free(ctx);
        }
      });
    });

    test('RAND_bytes fills buffer', () {
      using((arena) {
        final buf = arena.allocate<Uint8>(16);
        expect(openssl.RAND_bytes(buf.cast<UnsignedChar>(), 16), 1);
        expect(buf.asTypedList(16).any((b) => b != 0), isTrue);
      });
    });

    test('parses PEM certificate', () {
      using((arena) {
        final pemPtr = _sampleCertPem.toNativeUtf8(allocator: arena);
        final bio = openssl.BIO_new_mem_buf(pemPtr.cast(), -1);
        expect(bio, isNot(nullptr));
        try {
          final x509 = openssl.PEM_read_bio_X509(bio, nullptr, nullptr, nullptr);
          expect(x509, isNot(nullptr));
          openssl.X509_free(x509);
        } finally {
          openssl.BIO_free(bio);
        }
      });
    });
  });
}

const _sampleCertPem = '''
-----BEGIN CERTIFICATE-----
MIIBczCCAR0CFEqkMs9xq0qfdNflIpoqdDaOU/ThMA0GCSqGSIb3DQEBBAUAMDox
CzAJBgNVBAYTAkFVMQwwCgYDVQQIDANRTEQxHTAbBgNVBAMMFFNTTGVheSByc2Eg
dGVzdCBjZXJ0MCAXDTIwMDczMTE3MTM0NVoYDzIxMjAwNzA3MTcxMzQ1WjA6MQsw
CQYDVQQGEwJBVTEMMAoGA1UECAwDUUxEMR0wGwYDVQQDDBRTU0xlYXkgcnNhIHRl
c3QgY2VydDBcMA0GCSqGSIb3DQEBAQUAA0sAMEgCQQDUZKgYSMuJdiw2aIQIG4LD
vm9HbUnyJyj6WgPkpw98dVKTj0jo3F6n/e3anYzvSpOiPkTuvw209yslzJs40Sf7
AgMBAAEwDQYJKoZIhvcNAQEEBQADQQBV1bQAvyLvJQrNt7WEKmo/inigwjsvQYwd
nxmV6zWhqpQZmo86/ixumUa6zTlq+y4+wiiFngMZ7Bt0O769Nlzx
-----END CERTIFICATE-----
''';

void _checkResult(int result, String step) {
  if (result != 1) throw StateError('OpenSSL AES $step step failed, result: $result');
}

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
