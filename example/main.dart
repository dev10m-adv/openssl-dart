import 'dart:convert';
import 'dart:typed_data';

import 'package:openssl/crypto.dart';

Uint8List aes(Uint8List input, Uint8List key, Uint8List iv, {required bool encrypt}) =>
    aes256Cbc(input, key, iv, encrypt: encrypt);

void main() {
  final key = utf8.encode('Nc92PMoPjcIls5QoXeki5yIPuhjjWMcx');
  final iv = utf8.encode('1234567890123456');
  const message = 'Secret message for AES-256-CBC';
  final plaintext = utf8.encode(message);

  final encrypted = aes(plaintext, Uint8List.fromList(key), Uint8List.fromList(iv), encrypt: true);
  final decrypted = aes(encrypted, Uint8List.fromList(key), Uint8List.fromList(iv), encrypt: false);

  print('OpenSSL ${openSslLibcryptoVersion()}');
  print('cipher (b64): ${base64.encode(encrypted)}');
  print('roundtrip: ${utf8.decode(decrypted)}');
  print('sha256: ${toHex(sha256(Uint8List.fromList(plaintext)))}');
  print('random(16): ${toHex(randomBytes(16))}');
}
