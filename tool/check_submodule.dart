import 'dart:io';

import 'package:openssl/src/native_version.dart';
import 'package:openssl/src/prebuilt_paths.dart';

/// Verifies `native/third_party/openssl` is checked out at tag `openssl-<VERSION>`.
void main() {
  final packageRoot = Directory.current.uri;
  final version = readOpenSslVersion(packageRoot);
  final expectedTag = 'openssl-$version';
  final submodule = Directory.fromUri(nativeThirdPartyOpenSsl(packageRoot));

  if (!submodule.existsSync()) {
    stderr.writeln('check_submodule: ${submodule.path} missing (run git submodule update --init)');
    exit(1);
  }

  final result = Process.runSync(
    'git',
    ['-C', submodule.path, 'describe', '--tags', '--exact-match'],
    runInShell: Platform.isWindows,
  );
  if (result.exitCode != 0) {
    stderr.writeln('check_submodule: submodule not on an exact tag (expected $expectedTag)');
    stderr.writeln((result.stderr as String).trim());
    exit(1);
  }

  final tag = (result.stdout as String).trim();
  if (tag != expectedTag) {
    stderr.writeln('check_submodule: got tag $tag, expected $expectedTag');
    exit(1);
  }

  stdout.writeln('check_submodule: ok ($tag)');
}
