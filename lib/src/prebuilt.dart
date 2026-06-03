import 'dart:io';

import 'package:code_assets/code_assets.dart';

import 'prebuilt_paths.dart';

/// Returns a prebuilt [libcrypto] file for this target, if shipped under [native/prebuilt/].
File? findPrebuiltLibcrypto({
  required Uri packageRoot,
  required OS targetOS,
  required Architecture architecture,
  required LinkModePreference linkMode,
  IOSSdk? iosSdk,
}) {
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
  return candidate;
}
