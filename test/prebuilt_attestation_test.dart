import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:openssl/src/prebuilt_attestation.dart';
import 'package:test/test.dart';

void main() {
  test('buildVersionManifest and verifyArtifactSha256', () {
    final dir = Directory.systemTemp.createTempSync('openssl_attest_');
    addTearDown(() => dir.deleteSync(recursive: true));

    final artifact = File('${dir.path}/windows-arm64/libcrypto-test.dll');
    artifact.parent.createSync(recursive: true);
    artifact.writeAsBytesSync(List<int>.filled(5000, 7));

    final artifacts = collectVersionArtifacts(dir);
    expect(artifacts.keys, ['windows-arm64/libcrypto-test.dll']);

    final manifest = buildVersionManifest(version: '9.9.9', artifacts: artifacts);
    final err = verifyArtifactSha256(
      manifest: manifest,
      artifactRelativePath: 'windows-arm64/libcrypto-test.dll',
      file: artifact,
    );
    expect(err, isNull);

    artifact.writeAsBytesSync(List<int>.filled(5000, 8));
    final bad = verifyArtifactSha256(
      manifest: manifest,
      artifactRelativePath: 'windows-arm64/libcrypto-test.dll',
      file: artifact,
    );
    expect(bad, contains('sha256 mismatch'));
  });

  test('sign and verify manifest bytes', () async {
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final manifestBytes = utf8.encode('{"activeVersion":"1.0.0"}\n');

    final signature = await algorithm.sign(manifestBytes, keyPair: keyPair);
    final ok = await algorithm.verify(
      manifestBytes,
      signature: Signature(signature.bytes, publicKey: publicKey),
    );
    expect(ok, isTrue);
  });
}
