import 'dart:io';

import 'package:openssl/src/bootstrap_native.dart';

/// Build host prebuilts when Git LFS artifacts are missing.
Future<void> main(List<String> args) async {
  exit(await runBootstrapNative(args));
}
