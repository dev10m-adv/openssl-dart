import 'dart:io';

import 'package:code_assets/code_assets.dart';

import 'prebuilt_attestation.dart';
import 'prebuilt_paths.dart';

/// When `true`, fail if prebuilt checksum/signature verification fails.
bool get strictPrebuiltVerification =>
    Platform.environment['OPENSSL_VERIFY_PREBUILTS'] == '1' ||
    Platform.environment['OPENSSL_VERIFY_PREBUILTS'] == 'true';

/// Returns a prebuilt [libcrypto] file for this target, if shipped under [native/prebuilt/].
Future<File?> findPrebuiltLibcrypto({
  required Uri packageRoot,
  required OS targetOS,
  required Architecture architecture,
  required LinkModePreference linkMode,
  IOSSdk? iosSdk,
}) async {
  final candidate = resolvePrebuiltArtifact(
    packageRoot: packageRoot,
    targetOS: targetOS,
    architecture: architecture,
    linkMode: linkMode,
    iosSdk: iosSdk,
  );
  if (candidate == null) {
    return null;
  }
  if (candidate.lengthSync() < 4096) {
    final hint = _looksLikeLfsPointer(candidate)
        ? 'Git LFS pointer — run `dart run openssl:setup_prebuilts` or `git lfs pull` '
            '(use GIT_LFS_SKIP_SMUDGE=1 during pub get if smudge fails)'
        : 'file too small';
    print(
      'openssl: ignoring prebuilt at ${candidate.path} (${candidate.lengthSync()} bytes); '
      '$hint — will compile from source if the host toolchain allows',
    );
    return null;
  }

  final manifestFile = File.fromUri(versionManifestUri(packageRoot));
  if (manifestFile.existsSync()) {
    final error = await verifyPrebuiltArtifact(
      packageRoot: packageRoot,
      artifactFile: candidate,
      requireSignature: strictPrebuiltVerification,
    );
    if (error != null) {
      final message =
          'openssl: prebuilt verification failed for ${candidate.path}: $error';
      if (strictPrebuiltVerification) {
        throw StateError(message);
      }
      print('$message (set OPENSSL_VERIFY_PREBUILTS=1 to fail closed)');
    }
  }

  return candidate;
}

bool _looksLikeLfsPointer(File file) {
  try {
    final bytes = file.readAsBytesSync();
    if (bytes.length < 20) return false;
    return String.fromCharCodes(bytes.take(32)).startsWith('version https://git-lfs');
  } on Object {
    return false;
  }
}
