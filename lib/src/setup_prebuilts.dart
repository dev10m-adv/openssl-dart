import 'dart:io';

import 'native_version.dart';
import 'package_locator.dart';
import 'prebuilt_paths.dart';
import 'prebuilt_verify.dart';

/// Materializes Git LFS prebuilt libcrypto binaries for a git dependency checkout.
///
/// No-op with exit 0 when the package was installed from pub.dev (no LFS tree).
Future<int> runSetupPrebuilts(List<String> args) async {
  String? explicitPath;
  for (final arg in args) {
    if (arg.startsWith('--path=')) {
      explicitPath = arg.substring('--path='.length);
    } else if (arg == '--help' || arg == '-h') {
      _printUsage();
      return 0;
    }
  }

  final packageRoot = await locateOpenSslPackageRoot(explicitPath: explicitPath);
  stdout.writeln('openssl package root: ${packageRoot.path}');

  final versionRoot = Directory.fromUri(prebuiltVersionRootUri(packageRoot.uri));
  if (!versionRoot.existsSync()) {
    stdout.writeln(
      'No $prebuiltRoot/${readOpenSslVersion(packageRoot.uri)}/ in this package tree.\n'
      'pub.dev installs compile libcrypto from source on the first app build — nothing to set up.\n'
      'For fast builds, depend on git instead:\n'
      '  openssl:\n'
      '    git:\n'
      '      url: https://github.com/advforks/openssl-dart.git\n'
      '      ref: <tag-or-commit>',
    );
    return 0;
  }

  if (!await _hasGitLfs()) {
    stderr.writeln(
      'git-lfs is not installed. Install it, then re-run:\n'
      '  https://git-lfs.com/\n'
      'Or skip prebuilts — the build hook compiles from source when allowed.',
    );
    return 1;
  }

  final pull = await Process.run(
    'git',
    ['lfs', 'pull'],
    workingDirectory: packageRoot.path,
    runInShell: Platform.isWindows,
    environment: {...Platform.environment, 'GIT_LFS_SKIP_SMUDGE': '0'},
  );
  stdout.write(pull.stdout);
  stderr.write(pull.stderr);
  if (pull.exitCode != 0) {
    stderr.writeln(
      '\nsetup_prebuilts: git lfs pull failed.\n'
      'If `pub get` failed on LFS smudge, use:\n'
      '  GIT_LFS_SKIP_SMUDGE=1 flutter pub get\n'
      'then re-run: dart run openssl:setup_prebuilts',
    );
    return pull.exitCode;
  }

  return verifyPrebuilts(packageRoot.uri, allowPartial: true);
}

Future<bool> _hasGitLfs() async {
  final result = await Process.run(
    'git',
    ['lfs', 'version'],
    runInShell: Platform.isWindows,
  );
  return result.exitCode == 0;
}

void _printUsage() {
  stdout.writeln('''
Materialize Git LFS prebuilt libcrypto for the openssl package.

Usage:
  dart run openssl:setup_prebuilts [--path=<package-root>]

From a Flutter/Dart app with a git dependency, run after pub get.
From a git clone of openssl-dart, run in the repo root.

Tip: if pub get fails on LFS checkout:
  GIT_LFS_SKIP_SMUDGE=1 flutter pub get
  dart run openssl:setup_prebuilts
''');
}
