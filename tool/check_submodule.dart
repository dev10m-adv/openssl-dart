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

  final head = Process.runSync(
    'git',
    ['-C', submodule.path, 'rev-parse', 'HEAD'],
    runInShell: Platform.isWindows,
  );
  final tagRef = Process.runSync(
    'git',
    ['-C', submodule.path, 'rev-parse', expectedTag],
    runInShell: Platform.isWindows,
  );
  if (tagRef.exitCode != 0) {
    stderr.writeln(
      'check_submodule: tag $expectedTag not found (run: git -C ${submodule.path} fetch --tags origin)',
    );
    stderr.writeln((tagRef.stderr as String).trim());
    exit(1);
  }

  final headSha = (head.stdout as String).trim();
  final tagSha = (tagRef.stdout as String).trim();
  if (headSha != tagSha) {
    stderr.writeln('check_submodule: HEAD $headSha != $expectedTag ($tagSha)');
    exit(1);
  }

  stdout.writeln('check_submodule: ok ($expectedTag @ ${headSha.substring(0, 12)})');
}
