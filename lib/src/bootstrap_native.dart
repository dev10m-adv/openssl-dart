import 'dart:io';

import 'host_build_plan.dart';
import 'native_version.dart';
import 'package_locator.dart';
import 'prebuilt_attestation.dart';
import 'prebuilt_paths.dart';
import 'setup_prebuilts.dart';

enum _TripleOutcome { ok, skipped, failed, alreadyPresent }

class _TripleResult {
  _TripleResult({
    required this.triple,
    required this.outcome,
    this.detail,
    this.artifactPath,
    this.artifactBytes,
  });

  final String triple;
  final _TripleOutcome outcome;
  final String? detail;
  final String? artifactPath;
  final int? artifactBytes;
}

/// Builds or refreshes prebuilt libcrypto under [native/prebuilt/].
Future<int> runBootstrapNative(List<String> args) async {
  String? explicitPath;
  final triples = <String>[];
  var skipLfs = false;
  var buildAll = false;
  var verbose = Platform.environment['OPENSSL_BOOTSTRAP_VERBOSE'] == '1';

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
    } else if (arg == '--all') {
      buildAll = true;
    } else if (arg == '--verbose') {
      verbose = true;
    } else if (arg == '--help' || arg == '-h') {
      _printUsage();
      return 0;
    }
  }

  final packageRoot = await locateOpenSslPackageRoot(explicitPath: explicitPath);
  final version = readOpenSslVersion(packageRoot.uri);

  if (!skipLfs) {
    final lfsCode = await runSetupPrebuilts(
      explicitPath != null ? ['--path=${packageRoot.path}'] : [],
    );
    if (lfsCode != 0) {
      stderr.writeln('bootstrap_native: git lfs pull failed; continuing to local build.');
    }
  }

  final plan = buildAll ? planAllNativeBuilds() : null;
  final targets = triples.isNotEmpty
      ? triples
      : buildAll
          ? buildableTriplesOnHost()
          : [defaultHostTriple()];
  final buildOrder = _sortBuildTargets(targets);

  _printStartBanner(
    packageRoot: packageRoot.path,
    version: version,
    buildAll: buildAll,
    plan: plan,
    targets: buildOrder,
  );

  final results = <_TripleResult>[];
  for (final triple in buildOrder) {
    final entry = planTriple(triple);
    if (!entry.buildable) {
      results.add(_TripleResult(
        triple: triple,
        outcome: _TripleOutcome.skipped,
        detail: entry.skipReason,
      ));
      stdout.writeln('[skip] $triple — ${entry.skipReason}');
      continue;
    }

    if (hasPrebuiltForTriple(packageRoot.uri, triple)) {
      final artifact = _findPrebuiltArtifact(packageRoot.uri, triple);
      results.add(_TripleResult(
        triple: triple,
        outcome: _TripleOutcome.alreadyPresent,
        artifactPath: artifact?.$1,
        artifactBytes: artifact?.$2,
      ));
      stdout.writeln('[ok]   $triple — already present');
      continue;
    }

    stdout.writeln('[build] $triple ...');
    if (verbose) {
      stdout.writeln('       (verbose: compiler output below)');
    } else {
      stdout.writeln('       (quiet: ~5-10 min; full log in native/out/build-$triple.*.log)');
    }
    stdout.writeln('');
    try {
      await _buildPrebuilt(packageRoot.uri, triple, verbose: verbose);
      if (!hasPrebuiltForTriple(packageRoot.uri, triple)) {
        throw StateError('libcrypto artifact missing after build');
      }
      final artifact = _findPrebuiltArtifact(packageRoot.uri, triple);
      results.add(_TripleResult(
        triple: triple,
        outcome: _TripleOutcome.ok,
        artifactPath: artifact?.$1,
        artifactBytes: artifact?.$2,
      ));
      stdout.writeln('[ok]   $triple — built');
    } on Object catch (e) {
      results.add(_TripleResult(
        triple: triple,
        outcome: _TripleOutcome.failed,
        detail: '$e',
      ));
      stderr.writeln('[fail] $triple — $e');
    }
  }

  if (buildAll && plan != null) {
    for (final entry in plan) {
      if (entry.buildable) continue;
      if (results.any((r) => r.triple == entry.triple)) continue;
      results.add(_TripleResult(
        triple: entry.triple,
        outcome: _TripleOutcome.skipped,
        detail: entry.skipReason,
      ));
    }
  }

  await _writeReport(packageRoot.uri, version, results);
  _printSummary(results);

  final hostTriple = defaultHostTriple();
  final hostReady = results.any(
    (r) => r.triple == hostTriple && (r.outcome == _TripleOutcome.ok || r.outcome == _TripleOutcome.alreadyPresent),
  );
  if (!hostReady) {
    stderr.writeln('bootstrap_native: required host triple $hostTriple is not ready.');
    return 1;
  }
  return 0;
}

/// Returns true when [triple] has a smudged libcrypto shared library under prebuilt/.
bool hasPrebuiltForTriple(Uri packageRoot, String triple) {
  return _findPrebuiltArtifact(packageRoot, triple) != null;
}

(String path, int bytes)? _findPrebuiltArtifact(Uri packageRoot, String triple) {
  if (triple == 'ios-xcframework') {
    final dir = Directory.fromUri(prebuiltDirUri(packageRoot, triple));
    if (!dir.existsSync()) return null;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('libcrypto.dylib') && !entity.path.endsWith('libcrypto.a')) {
        continue;
      }
      if (entity.lengthSync() >= 4096) {
        return (entity.path, entity.lengthSync());
      }
    }
    return null;
  }

  final dir = Directory.fromUri(prebuiltDirUri(packageRoot, triple));
  if (!dir.existsSync()) return null;
  for (final entity in dir.listSync()) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    if (!isLibcryptoLibraryFileName(name)) continue;
    if (entity.lengthSync() >= 4096) {
      return (entity.path, entity.lengthSync());
    }
  }
  return null;
}

void _printStartBanner({
  required String packageRoot,
  required String version,
  required bool buildAll,
  required List<NativeBuildPlanEntry>? plan,
  required List<String> targets,
}) {
  stdout.writeln('');
  stdout.writeln('=== OpenSSL native prebuilt bootstrap ===');
  stdout.writeln('Package : $packageRoot');
  stdout.writeln('Version : $version');
  stdout.writeln('Host    : ${Platform.operatingSystem} (${defaultHostTriple()})');
  stdout.writeln('Mode    : ${buildAll ? 'build all triples possible on this host' : 'host triple only'}');
  stdout.writeln('');
  if (buildAll && plan != null) {
    stdout.writeln('Plan:');
    for (final entry in plan) {
      if (entry.buildable) {
        stdout.writeln('  [build]  ${entry.triple}');
      } else {
        stdout.writeln('  [skip]   ${entry.triple} - ${entry.skipReason}');
      }
    }
    stdout.writeln('');
  } else {
    stdout.writeln('Targets: ${targets.join(', ')}');
    stdout.writeln('');
  }
}

void _printSummary(List<_TripleResult> results) {
  stdout.writeln('');
  stdout.writeln('=== Native prebuilt summary ===');
  var built = 0;
  var present = 0;
  var skipped = 0;
  var failed = 0;

  for (final r in results) {
    switch (r.outcome) {
      case _TripleOutcome.ok:
        built++;
        final size = r.artifactBytes != null ? _formatBytes(r.artifactBytes!) : '?';
        stdout.writeln('  OK       ${r.triple}  ${r.artifactPath ?? ''} ($size)');
      case _TripleOutcome.alreadyPresent:
        present++;
        final size = r.artifactBytes != null ? _formatBytes(r.artifactBytes!) : '?';
        stdout.writeln('  CACHED   ${r.triple}  ${r.artifactPath ?? ''} ($size)');
      case _TripleOutcome.skipped:
        skipped++;
        stdout.writeln('  SKIPPED  ${r.triple}  ${r.detail ?? ''}');
      case _TripleOutcome.failed:
        failed++;
        stdout.writeln('  FAILED   ${r.triple}  ${r.detail ?? ''}');
    }
  }

  stdout.writeln('');
  stdout.writeln(
    'Saved $built new, $present cached, $skipped skipped (other host), $failed failed.',
  );
  stdout.writeln('=== done ===');
  stdout.writeln('');
}

Future<void> _writeReport(Uri packageRoot, String version, List<_TripleResult> results) async {
  final reportDir = packageRoot.resolve('native/out/');
  await Directory.fromUri(reportDir).create(recursive: true);
  final reportFile = File.fromUri(reportDir.resolve('bootstrap-report.txt'));
  final buffer = StringBuffer()
    ..writeln('OpenSSL native prebuilt bootstrap report')
    ..writeln('Version: $version')
    ..writeln('Host: ${Platform.operatingSystem}')
    ..writeln('Time: ${DateTime.now().toIso8601String()}')
    ..writeln('');
  for (final r in results) {
    buffer.writeln('${r.outcome.name.toUpperCase()}  ${r.triple}  ${r.detail ?? r.artifactPath ?? ''}');
  }
  await reportFile.writeAsString(buffer.toString());
  stdout.writeln('Report saved: ${reportFile.path}');
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}

List<String> _sortBuildTargets(List<String> triples) {
  final host = defaultHostTriple();
  int rank(String triple) {
    if (triple == host) return 0;
    if (triple.startsWith('windows-')) return 1;
    if (triple.startsWith('android-')) return 2;
    return 3;
  }

  final sorted = [...triples]
    ..sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.compareTo(b);
    });
  return sorted;
}

Future<void> _buildPrebuilt(Uri packageRoot, String triple, {required bool verbose}) async {
  final buildDir = packageRoot.resolve('native/build/');
  if (Platform.isWindows) {
    if (triple == 'windows-x64' || triple == 'windows-arm64') {
      final script = buildDir.resolve('windows.ps1').toFilePath(windows: true);
      final pwsh = await _resolvePwsh();
      final args = <String>[
        if (pwsh == 'powershell') ...['-NoProfile', '-ExecutionPolicy', 'Bypass'],
        '-File',
        script,
        '-Triple',
        triple,
        if (!verbose) '-Quiet',
      ];
      await _runScript(
        pwsh,
        args,
        packageRoot,
        verbose: verbose,
        logTriple: triple,
      );
      return;
    }
    if (triple.startsWith('android-')) {
      final script = buildDir.resolve('android.ps1').toFilePath(windows: true);
      final pwsh = await _resolvePwsh();
      final args = <String>[
        if (pwsh == 'powershell') ...['-NoProfile', '-ExecutionPolicy', 'Bypass'],
        '-File',
        script,
        '-Triple',
        triple,
        if (!verbose) '-Quiet',
      ];
      await _runScript(
        pwsh,
        args,
        packageRoot,
        verbose: verbose,
        logTriple: triple,
      );
      return;
    }
    throw UnsupportedError('Cannot build $triple on Windows host.');
  }

  if (Platform.isLinux) {
    if (triple.startsWith('linux-')) {
      await _runScript(
        'bash',
        [buildDir.resolve('linux.sh').toFilePath()],
        packageRoot,
        environment: {'TRIPLE': triple},
        verbose: verbose,
      );
      return;
    }
    if (triple.startsWith('android-')) {
      await _runScript(
        'bash',
        [buildDir.resolve('android.sh').toFilePath()],
        packageRoot,
        environment: {'TRIPLE': triple},
        verbose: verbose,
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
        verbose: verbose,
      );
      return;
    }
    if (triple.startsWith('linux-')) {
      await _runScript(
        'bash',
        [buildDir.resolve('linux.sh').toFilePath()],
        packageRoot,
        environment: {'TRIPLE': triple},
        verbose: verbose,
      );
      return;
    }
    if (triple.startsWith('android-')) {
      await _runScript(
        'bash',
        [buildDir.resolve('android.sh').toFilePath()],
        packageRoot,
        environment: {'TRIPLE': triple},
        verbose: verbose,
      );
      return;
    }
  }

  throw UnsupportedError('Cannot build $triple on ${Platform.operatingSystem} host.');
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

String? _resolveBuildLogPath(Uri packageRoot, String triple) {
  final outDir = Directory.fromUri(packageRoot.resolve('native/out/'));
  if (!outDir.existsSync()) return null;

  File? newest;
  for (final entity in outDir.listSync()) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    if (!name.startsWith('build-$triple')) continue;
    if (newest == null || entity.lastModifiedSync().isAfter(newest.lastModifiedSync())) {
      newest = entity;
    }
  }
  return newest?.path;
}

Future<void> _runScript(
  String executable,
  List<String> arguments,
  Uri workingDirectory, {
  Map<String, String>? environment,
  required bool verbose,
  String? logTriple,
}) async {
  if (verbose) {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory.toFilePath(),
      environment: {...Platform.environment, ...?environment},
      runInShell: Platform.isWindows,
    );
    await Future.wait([
      process.stdout.forEach(stdout.add),
      process.stderr.forEach(stderr.add),
    ]);
    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw ProcessException(executable, arguments, 'exit code $exitCode', exitCode);
    }
    return;
  }

  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory.toFilePath(),
    environment: {...Platform.environment, ...?environment},
    runInShell: Platform.isWindows,
  );
  if (result.exitCode != 0) {
    final message = StringBuffer('exit code ${result.exitCode}');
    final logPath = logTriple != null ? _resolveBuildLogPath(workingDirectory, logTriple) : null;
    if (logPath != null) {
      final log = File(logPath);
      if (log.existsSync()) {
        var content = log.readAsStringSync();
        if (content.startsWith('\uFEFF')) {
          content = content.substring(1);
        }
        final lines = content
            .split(RegExp(r'\r?\n'))
            .where((line) => line.trim().isNotEmpty)
            .toList();
        final tail = lines.length > 40 ? lines.sublist(lines.length - 40) : lines;
        message
          ..writeln()
          ..writeln('--- log tail ($logPath) ---')
          ..writeln(tail.join('\n'));
      }
    } else {
      final out = '${result.stdout}'.trim();
      final err = '${result.stderr}'.trim();
      if (out.isNotEmpty) {
        message
          ..writeln()
          ..writeln(out);
      }
      if (err.isNotEmpty) {
        message
          ..writeln()
          ..writeln(err);
      }
    }
    throw ProcessException(executable, arguments, message.toString(), result.exitCode);
  }
}

void _printUsage() {
  stdout.writeln('''
Build local libcrypto prebuilts for the openssl package (no git commit required).

Usage:
  dart run openssl:bootstrap_native [--all] [--path=<package-root>] [--triple=<name>] [--skip-lfs]

  --all       Build every triple this host can compile; skip others with a log line.
  --triple    Build one triple (repeatable via multiple --triple flags).
  --verbose   Stream full compiler output (default: quiet, logs under native/out/).

Run from your app after pub get. Set OPENSSL_SKIP_NATIVE_HOOK=1 during openssl tooling.
Set OPENSSL_BOOTSTRAP_VERBOSE=1 for verbose output without --verbose.
''');
}
