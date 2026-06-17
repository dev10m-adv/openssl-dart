import 'dart:io';

import 'package_locator.dart';
import 'prebuilt_attestation.dart';
import 'prebuilt_paths.dart';
import 'setup_prebuilts.dart';

/// Builds or refreshes host prebuilt libcrypto under [native/prebuilt/].
///
/// Use after `pub get` when LFS prebuilts are absent (typical git dependency).
Future<int> runBootstrapNative(List<String> args) async {
  String? explicitPath;
  final triples = <String>[];
  var skipLfs = false;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith('--path=')) {
      explicitPath = arg.substring('--path='.length);
    } else if (arg == '--triple' && i + 1 < args.length) {
      triples.add(args[++i]);
    } else if (arg.startsWith('--triple=')) {
      triples.add(arg.substring('--triple='.length));
    } else if (arg == '--skip-lfs') {
      skipLfs = true;
    } else if (arg == '--help' || arg == '-h') {
      _printUsage();
      return 0;
    }
  }

  final packageRoot = await locateOpenSslPackageRoot(explicitPath: explicitPath);
  stdout.writeln('openssl package root: ${packageRoot.path}');

  if (!skipLfs) {
    final lfsCode = await runSetupPrebuilts(
      explicitPath != null ? ['--path=${packageRoot.path}'] : [],
    );
    if (lfsCode != 0) {
      stderr.writeln('bootstrap_native: git lfs pull failed; continuing to local build.');
    }
  }

  final targets = triples.isEmpty ? [_defaultHostTriple()] : triples;
  for (final triple in targets) {
    if (hasPrebuiltForTriple(packageRoot.uri, triple)) {
      stdout.writeln('bootstrap_native: prebuilt ok for $triple');
      continue;
    }
    stdout.writeln('bootstrap_native: building prebuilt for $triple ...');
    try {
      await _buildPrebuilt(packageRoot.uri, triple);
    } on Object catch (e) {
      stderr.writeln('bootstrap_native: build failed for $triple: $e');
      return 1;
    }
    if (!hasPrebuiltForTriple(packageRoot.uri, triple)) {
      stderr.writeln('bootstrap_native: no libcrypto artifact after build ($triple)');
      return 1;
    }
    stdout.writeln('bootstrap_native: built $triple');
  }

  return 0;
}

/// Returns true when [triple] has a smudged libcrypto shared library under prebuilt/.
bool hasPrebuiltForTriple(Uri packageRoot, String triple) {
  if (triple == 'ios-xcframework') {
    final dir = Directory.fromUri(prebuiltDirUri(packageRoot, triple));
    if (!dir.existsSync()) return false;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('libcrypto.dylib') && !entity.path.endsWith('libcrypto.a')) {
        continue;
      }
      if (entity.lengthSync() >= 4096) return true;
    }
    return false;
  }

  final dir = Directory.fromUri(prebuiltDirUri(packageRoot, triple));
  if (!dir.existsSync()) return false;
  for (final entity in dir.listSync()) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    if (!isLibcryptoLibraryFileName(name)) continue;
    if (entity.lengthSync() >= 4096) return true;
  }
  return false;
}

String _defaultHostTriple() {
  if (Platform.isWindows) {
    final arch = (Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '').toUpperCase();
    return arch.contains('ARM64') ? 'windows-arm64' : 'windows-x64';
  }
  if (Platform.isLinux) {
    final machine = Platform.environment['PROCESSOR_ARCHITECTURE'] ??
        _unameMachine() ??
        'x86_64';
    return machine.toLowerCase().contains('aarch64') || machine.toLowerCase().contains('arm64')
        ? 'linux-arm64'
        : 'linux-x64';
  }
  if (Platform.isMacOS) {
    return 'macos-universal';
  }
  throw UnsupportedError('bootstrap_native: unsupported host OS ${Platform.operatingSystem}');
}

String? _unameMachine() {
  try {
    final result = Process.runSync('uname', ['-m']);
    if (result.exitCode == 0) {
      return (result.stdout as String).trim();
    }
  } on Object {
    // ignore
  }
  return null;
}

Future<void> _buildPrebuilt(Uri packageRoot, String triple) async {
  final buildDir = packageRoot.resolve('native/build/');
  if (Platform.isWindows) {
    if (!(triple == 'windows-x64' || triple == 'windows-arm64')) {
      throw UnsupportedError('Windows host can only build windows-x64 or windows-arm64');
    }
    final script = buildDir.resolve('windows.ps1').toFilePath(windows: true);
    final pwsh = await _resolvePwsh();
    final args = pwsh == 'powershell'
        ? ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script, '-Triple', triple]
        : ['-File', script, '-Triple', triple];
    await _runScript(pwsh, args, packageRoot);
    return;
  }

  if (Platform.isLinux) {
    if (triple.startsWith('linux-')) {
      await _runScript(
        'bash',
        [buildDir.resolve('linux.sh').toFilePath()],
        packageRoot,
        environment: {'TRIPLE': triple},
      );
      return;
    }
    if (triple.startsWith('android-')) {
      await _runScript(
        'bash',
        [buildDir.resolve('android.sh').toFilePath()],
        packageRoot,
        environment: {'TRIPLE': triple},
      );
      return;
    }
  }

  if (Platform.isMacOS) {
    if (triple == 'macos-universal' || triple == 'ios-xcframework') {
      await _runScript(
        'bash',
        [buildDir.resolve('macos.sh').toFilePath()],
        packageRoot,
        environment: {'TRIPLE': triple},
      );
      return;
    }
  }

  throw UnsupportedError(
    'Cannot build $triple on ${Platform.operatingSystem} host. '
    'Use CI release artifacts or a matching host.',
  );
}

Future<String> _resolvePwsh() async {
  for (final candidate in ['pwsh', 'powershell']) {
    try {
      final result = await Process.run(
        candidate,
        ['-NoProfile', '-Command', r'$PSVersionTable.PSVersion.Major'],
        runInShell: Platform.isWindows,
      );
      if (result.exitCode == 0) return candidate;
    } on Object {
      // try next
    }
  }
  throw StateError('pwsh or powershell not found on PATH');
}

Future<void> _runScript(
  String executable,
  List<String> arguments,
  Uri workingDirectory, {
  Map<String, String>? environment,
}) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory.toFilePath(),
    environment: {...Platform.environment, ...?environment},
    runInShell: Platform.isWindows,
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) {
    throw ProcessException(executable, arguments, result.stderr, result.exitCode);
  }
}

void _printUsage() {
  stdout.writeln('''
Build local libcrypto prebuilts for the openssl package (no git commit required).

Usage:
  dart run openssl:bootstrap_native [--path=<package-root>] [--triple=<name>] [--skip-lfs]

Defaults to the host triple (e.g. windows-x64). Run from your app after pub get.

Tip: set OPENSSL_SKIP_NATIVE_HOOK=1 while running openssl tooling to avoid hook compile during pub.
''');
}
