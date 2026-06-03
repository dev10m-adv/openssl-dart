import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

/// Generates Ed25519 keypair for prebuilt manifest signing.
/// Commit the public key file; store private key in GitHub secret PREBUILT_SIGNING_PRIVATE_KEY.
void main() async {
  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPair();
  final privateBytes = await keyPair.extractPrivateKeyBytes();
  final publicKey = await keyPair.extractPublicKey();

  final publicPath = 'native/src/prebuilt_signing_public.key';
  File(publicPath).writeAsStringSync('${base64Encode(publicKey.bytes)}\n');

  stdout.writeln('Wrote public key: $publicPath');
  stdout.writeln('');
  stdout.writeln('Add GitHub secret PREBUILT_SIGNING_PRIVATE_KEY (base64 private seed):');
  stdout.writeln(base64Encode(privateBytes));
  stdout.writeln('');
  stdout.writeln('Never commit the private key. Rotate by regenerating and updating the secret.');
}
