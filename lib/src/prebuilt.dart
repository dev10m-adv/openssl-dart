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
    print(
      'openssl: ignoring prebuilt at ${candidate.path} (${candidate.lengthSync()} bytes); '
      'run `git lfs pull` or compile from source',
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
