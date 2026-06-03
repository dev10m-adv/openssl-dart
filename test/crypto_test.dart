import 'dart:convert';
import 'dart:typed_data';

import 'package:openssl/crypto.dart';
import 'package:test/test.dart';

void main() {
  test('openSslLibcryptoVersion reports 3.5.x', () {
    expect(openSslLibcryptoVersion(), startsWith('3.5.'));
  });

  test('aes256Cbc roundtrip', () {
    const message = 'test message';
    final key = Uint8List.fromList(utf8.encode('Nc92PMoPjcIls5QoXeki5yIPuhjjWMcx'));
    final iv = Uint8List.fromList(utf8.encode('1234567890123456'));
    final plain = Uint8List.fromList(utf8.encode(message));
    final enc = aes256Cbc(plain, key, iv, encrypt: true);
    final dec = aes256Cbc(enc, key, iv, encrypt: false);
    expect(utf8.decode(dec), message);
  });

  test('sha256 matches known digest of "hello"', () {
    final digest = sha256(Uint8List.fromList(utf8.encode('hello')));
    expect(
      toHex(digest),
      '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
    );
  });

  test('sha512 produces 64-byte digest', () {
    final digest = sha512(Uint8List.fromList(utf8.encode('hello')));
    expect(digest.length, 64);
  });

  test('randomBytes returns requested length and varies', () {
    final a = randomBytes(32);
    final b = randomBytes(32);
    expect(a.length, 32);
    expect(b.length, 32);
    expect(a, isNot(equals(b)));
    expect(randomBytes(0), isEmpty);
  });
}
