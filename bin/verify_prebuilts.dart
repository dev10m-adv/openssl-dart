import 'dart:io';

import 'package:openssl/src/prebuilt_verify.dart';

/// Published CLI — same as `dart run tool/verify_prebuilts.dart` in a git clone.
Future<void> main(List<String> args) async {
  final allowPartial = args.contains('--allow-partial');
  final requireSignature = args.contains('--require-signature');
  final packageRoot = Directory.current.uri;
  exit(await verifyPrebuilts(
    packageRoot,
    allowPartial: allowPartial,
    requireSignature: requireSignature,
  ));
}
