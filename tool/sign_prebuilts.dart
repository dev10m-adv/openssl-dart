import 'dart:convert';
import 'dart:io';

import 'package:openssl/src/native_version.dart';
import 'package:openssl/src/prebuilt_attestation.dart';
import 'package:openssl/src/prebuilt_paths.dart';

/// Writes [native/prebuilt/<version>/manifest.json] with per-artifact SHA-256.
/// Signs [manifest.json.sig] when [PREBUILT_SIGNING_PRIVATE_KEY] is set (base64 seed).
///
/// `--check`: exit 1 if manifest or signature would change.
/// `--allow-partial`: in `--check`, only verify on-disk artifacts match the manifest.
void main(List<String> args) async {
  final checkOnly = args.contains('--check');
  final allowPartial = args.contains('--allow-partial');
  final packageRoot = Directory.current.uri;
  final version = readOpenSslVersion(packageRoot);
  final versionRoot = Directory.fromUri(prebuiltVersionRootUri(packageRoot));
  final artifacts = collectVersionArtifacts(versionRoot);
  final manifest = buildVersionManifest(version: version, artifacts: artifacts);
  final body = encodeManifestJson(manifest);
  final manifestFile = File.fromUri(versionManifestUri(packageRoot));
  final sigFile = File.fromUri(versionManifestSigUri(packageRoot));

  final privateKey = await loadSigningPrivateKeyFromEnv();
  List<int>? newSig;
  if (privateKey != null) {
    newSig = await signManifestBytes(utf8.encode(body));
  }

  final currentBody = manifestFile.existsSync() ? manifestFile.readAsStringSync() : '';
  final currentSig = sigFile.existsSync() ? sigFile.readAsStringSync().trim() : '';
  final newSigB64 = newSig != null ? base64Encode(newSig) : '';

  var manifestOk = currentBody == body;
  if (checkOnly && allowPartial && manifestFile.existsSync()) {
    manifestOk = _partialManifestMatches(
      manifest: jsonDecode(currentBody) as Map<String, dynamic>,
      artifacts: artifacts,
    );
  }
  final sigOk = newSig == null ? currentSig.isEmpty : currentSig == newSigB64;

  if (manifestOk && sigOk) {
    stdout.writeln('sign_prebuilts: ok');
    await _syncRootIndex(packageRoot, version);
    return;
  }

  if (checkOnly) {
    stderr.writeln('sign_prebuilts: out of date; run `dart run tool/sign_prebuilts.dart`');
    exit(1);
  }

  manifestFile.parent.createSync(recursive: true);
  manifestFile.writeAsStringSync(body);
  if (newSig != null) {
    sigFile.writeAsStringSync('$newSigB64\n');
    stdout.writeln('sign_prebuilts: wrote ${sigFile.path}');
  } else {
    stderr.writeln('sign_prebuilts: PREBUILT_SIGNING_PRIVATE_KEY not set; skipped signature');
  }
  stdout.writeln('sign_prebuilts: wrote ${manifestFile.path} (${artifacts.length} artifacts)');
  await _syncRootIndex(packageRoot, version);
}

bool _partialManifestMatches({
  required Map<String, dynamic> manifest,
  required Map<String, File> artifacts,
}) {
  for (final entry in artifacts.entries) {
    final err = verifyArtifactSha256(
      manifest: manifest,
      artifactRelativePath: entry.key,
      file: entry.value,
    );
    if (err != null) {
      return false;
    }
  }
  return true;
}

Future<void> _syncRootIndex(Uri packageRoot, String version) async {
  final index = File.fromUri(prebuiltManifestUri(packageRoot));
  final expected = encodeManifestJson({
    'activeVersion': version,
    'triples': requiredPrebuiltTriples,
  });
  index.parent.createSync(recursive: true);
  index.writeAsStringSync(expected);
}
