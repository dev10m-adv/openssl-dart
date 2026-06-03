import 'dart:io';

import 'package:openssl/src/setup_prebuilts.dart';

/// Pull Git LFS prebuilts for a git [openssl] dependency (app pub cache or clone root).
Future<void> main(List<String> args) async {
  exit(await runSetupPrebuilts(args));
}
