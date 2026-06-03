import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as crypto;

import 'native_version.dart';
import 'prebuilt_paths.dart';

const prebuiltSigningPublicKeyId = 'prebuilt-default';
const prebuiltSigningPublicKeyFile = 'native/src/prebuilt_signing_public.key';
const versionManifestName = 'manifest.json';
const versionManifestSigName = 'manifest.json.sig';

Uri versionManifestUri(Uri packageRoot) {
  final version = readOpenSslVersion(packageRoot);
  return packageRoot.resolve('$prebuiltRoot/$version/$versionManifestName');
}

Uri versionManifestSigUri(Uri packageRoot) {
  final version = readOpenSslVersion(packageRoot);
  return packageRoot.resolve('$prebuiltRoot/$version/$versionManifestSigName');
}

Uri prebuiltSigningPublicKeyUri(Uri packageRoot) =>
    packageRoot.resolve(prebuiltSigningPublicKeyFile);

/// Collects libcrypto artifact paths (relative to version root) under [versionRoot].
Map<String, File> collectVersionArtifacts(Directory versionRoot) {
  final artifacts = <String, File>{};
  if (!versionRoot.existsSync()) {
    return artifacts;
  }
  for (final entity in versionRoot.listSync(recursive: true)) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    if (name == versionManifestName ||
        name == versionManifestSigName ||
        name == '.build-hash' ||
        name.endsWith('.md')) {
      continue;
    }
    if (!_isLibcryptoArtifact(name)) continue;
    if (entity.lengthSync() < 4096) continue;

    final relative = entity.path
        .substring(versionRoot.path.length)
        .replaceAll(r'\', '/')
        .replaceFirst(RegExp(r'^/'), '');
    artifacts[relative] = entity;
  }
  return artifacts;
}

/// True for paths that should be large LFS-backed libcrypto binaries (not headers).
bool isPrebuiltBinaryArtifactPath(String relativePath) {
  final name = relativePath.split('/').last;
  if (name == '.build-hash' ||
      name == 'manifest.json' ||
      name == 'manifest.json.sig' ||
      name == 'README.md') {
    return false;
  }
  if (name.contains('libcrypto') &&
      (name.endsWith('.dll') ||
          name.endsWith('.so') ||
          name.endsWith('.dylib') ||
          name.endsWith('.a'))) {
    return true;
  }
  return name == 'OpenSSL.xcframework' || name.endsWith('.xcframework');
}

bool _isLibcryptoArtifact(String name) {
  if (name.contains('libcrypto') &&
      (name.endsWith('.dll') ||
          name.endsWith('.so') ||
          name.endsWith('.dylib') ||
          name.endsWith('.a'))) {
    return true;
  }
  return name == 'OpenSSL.xcframework' || name.endsWith('.xcframework');
}

String sha256HexFile(File file) {
  final digest = crypto.sha256.convert(file.readAsBytesSync());
  return digest.toString();
}

/// Builds manifest JSON map for [version] from files on disk.
Map<String, dynamic> buildVersionManifest({
  required String version,
  required Map<String, File> artifacts,
}) {
  final artifactEntries = <String, dynamic>{};
  final sortedPaths = artifacts.keys.toList()..sort();
  for (final path in sortedPaths) {
    final file = artifacts[path]!;
    artifactEntries[path] = {
      'sha256': sha256HexFile(file),
      'bytes': file.lengthSync(),
    };
  }
  return {
    'activeVersion': version,
    'algorithm': 'sha256',
    'publicKeyId': prebuiltSigningPublicKeyId,
    'triples': requiredPrebuiltTriples,
    'artifacts': artifactEntries,
  };
}

String encodeManifestJson(Map<String, dynamic> manifest) {
  const encoder = JsonEncoder.withIndent('  ');
  return '${encoder.convert(manifest)}\n';
}

Map<String, dynamic> readVersionManifest(Uri packageRoot) {
  final file = File.fromUri(versionManifestUri(packageRoot));
  if (!file.existsSync()) {
    throw StateError('Missing ${file.path}');
  }
  final body = file.readAsStringSync();
  if (_isGitLfsPointer(body)) {
    throw StateError('${file.path} is a Git LFS pointer (run git lfs pull)');
  }
  return jsonDecode(body) as Map<String, dynamic>;
}

bool _isGitLfsPointer(String text) =>
    text.trimLeft().startsWith('version https://git-lfs.github.com/spec/v1');

/// Verifies [file] matches [manifest] entry at [artifactRelativePath]. Returns error or null.
String? verifyArtifactSha256({
  required Map<String, dynamic> manifest,
  required String artifactRelativePath,
  required File file,
}) {
  final artifacts = manifest['artifacts'] as Map<String, dynamic>?;
  if (artifacts == null) {
    return 'manifest has no artifacts section';
  }
  final entry = artifacts[artifactRelativePath];
  if (entry == null) {
    return 'manifest missing entry for $artifactRelativePath';
  }
  Map<String, dynamic> meta;
  if (entry is String) {
    meta = {'sha256': entry};
  } else if (entry is Map<String, dynamic>) {
    meta = entry;
  } else {
    return 'invalid manifest entry for $artifactRelativePath';
  }
  final expected = meta['sha256'] as String?;
  if (expected == null) {
    return 'manifest entry missing sha256 for $artifactRelativePath';
  }
  final actual = sha256HexFile(file);
  if (actual != expected.toLowerCase()) {
    return 'sha256 mismatch for $artifactRelativePath (expected $expected, got $actual)';
  }
  return null;
}

/// Resolves relative artifact path from version root to [artifactFile].
String artifactRelativePath(Uri packageRoot, File artifactFile) {
  final versionRoot = Directory.fromUri(prebuiltVersionRootUri(packageRoot));
  return artifactFile.path
      .substring(versionRoot.path.length)
      .replaceAll(r'\', '/')
      .replaceFirst(RegExp(r'^/'), '');
}

Future<SimplePublicKey?> loadSigningPublicKey(Uri packageRoot) async {
  final file = File.fromUri(prebuiltSigningPublicKeyUri(packageRoot));
  if (!file.existsSync()) {
    return null;
  }
  final line = file.readAsStringSync().trim();
  if (line.isEmpty) {
    return null;
  }
  final bytes = base64Decode(line);
  return SimplePublicKey(bytes, type: KeyPairType.ed25519);
}

Future<SimpleKeyPair?> loadSigningPrivateKeyFromEnv() async {
  final raw = Platform.environment['PREBUILT_SIGNING_PRIVATE_KEY'];
  if (raw == null || raw.trim().isEmpty) {
    return null;
  }
  final bytes = base64Decode(raw.trim());
  final seed = bytes.length >= 32 ? bytes.sublist(0, 32) : bytes;
  return Ed25519().newKeyPairFromSeed(seed);
}

Future<List<int>> signManifestBytes(List<int> manifestBytes) async {
  final keyPair = await loadSigningPrivateKeyFromEnv();
  if (keyPair == null) {
    throw StateError('PREBUILT_SIGNING_PRIVATE_KEY not set');
  }
  final algorithm = Ed25519();
  final signature = await algorithm.sign(manifestBytes, keyPair: keyPair);
  return signature.bytes;
}

Future<String?> verifyManifestSignature(Uri packageRoot) async {
  final manifestFile = File.fromUri(versionManifestUri(packageRoot));
  final sigFile = File.fromUri(versionManifestSigUri(packageRoot));
  if (!sigFile.existsSync()) {
    return null;
  }
  final publicKey = await loadSigningPublicKey(packageRoot);
  if (publicKey == null) {
    return 'manifest.json.sig present but $prebuiltSigningPublicKeyFile missing';
  }
  final manifestBytes = manifestFile.readAsBytesSync();
  final sigText = sigFile.readAsStringSync().trim();
  if (_isGitLfsPointer(sigText)) {
    return '${sigFile.path} is a Git LFS pointer (run git lfs pull)';
  }
  List<int> sigBytes;
  try {
    sigBytes = base64Decode(sigText);
  } on FormatException {
    return '${sigFile.path} is not valid base64';
  }
  final algorithm = Ed25519();
  final ok = await algorithm.verify(
    manifestBytes,
    signature: Signature(sigBytes, publicKey: publicKey),
  );
  if (!ok) {
    return 'manifest.json.sig invalid for ${manifestFile.path}';
  }
  return null;
}

/// Full verification for [artifactFile]; returns first error or null.
Future<String?> verifyPrebuiltArtifact({
  required Uri packageRoot,
  required File artifactFile,
  bool requireSignature = false,
}) async {
  Map<String, dynamic> manifest;
  try {
    manifest = readVersionManifest(packageRoot);
  } catch (e) {
    return e.toString();
  }

  if (requireSignature) {
    final sigError = await verifyManifestSignature(packageRoot);
    if (sigError != null) {
      return sigError;
    }
    final sigFile = File.fromUri(versionManifestSigUri(packageRoot));
    if (!sigFile.existsSync()) {
      return 'OPENSSL_VERIFY_PREBUILTS requires ${sigFile.path}';
    }
  } else {
    await verifyManifestSignature(packageRoot);
  }

  final relative = artifactRelativePath(packageRoot, artifactFile);
  return verifyArtifactSha256(
    manifest: manifest,
    artifactRelativePath: relative,
    file: artifactFile,
  );
}
