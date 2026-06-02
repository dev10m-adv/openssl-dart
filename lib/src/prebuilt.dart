import 'dart:io';

import 'package:code_assets/code_assets.dart';

import 'build_target.dart';

/// Returns a prebuilt [libcrypto] file for this target, if shipped under [prebuilt/].
File? findPrebuiltLibcrypto({
  required Uri packageRoot,
  required OS targetOS,
  required Architecture architecture,
  required LinkModePreference linkMode,
  IOSSdk? iosSdk,
}) {
  final key = prebuiltTripleKey(
    targetOS: targetOS,
    architecture: architecture,
    linkMode: linkMode,
    iosSdk: iosSdk,
  );
  final libName = resolveLibFileName(targetOS, architecture, linkMode);
  final candidate = File.fromUri(packageRoot.resolve('prebuilt/$key/$libName'));
  return candidate.existsSync() ? candidate : null;
}
