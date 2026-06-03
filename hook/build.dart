import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

import '../lib/src/android_ndk.dart';
import '../lib/src/build_target.dart';
import '../lib/src/openssl_source.dart';
import '../lib/src/prebuilt.dart';
import '../lib/src/prebuilt_paths.dart';

const perlDownloadUrlLegacy =
    'https://strawberryperl.com/download/5.14.2.1/strawberry-perl-5.14.2.1-64bit-portable.zip';
const perlDownloadUrlModern =
    'https://github.com/StrawberryPerl/Perl-Dist-Strawberry/releases/download/SP_54021_64bit_UCRT/strawberry-perl-5.40.2.1-64bit-portable.zip';
const jomDownloadUrl = 'https://download.qt.io/official_releases/jom/jom_1_1_5.zip';

Map<String, String> environment = {};

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final targetOS = input.config.code.targetOS;
    final architecture = input.config.code.targetArchitecture;
    final linkMode = input.config.code.linkModePreference;
    final iosSdk = targetOS == OS.iOS ? input.config.code.iOS.targetSdk : null;
    final libName = resolveLibFileName(targetOS, architecture, linkMode);
    final outputDir = input.outputDirectoryShared;
    final packageRoot = input.packageRoot;

    final prebuilt = await findPrebuiltLibcrypto(
      packageRoot: packageRoot,
      targetOS: targetOS,
      architecture: architecture,
      linkMode: linkMode,
      iosSdk: iosSdk,
    );

    late final String outputLibName;
    if (prebuilt != null) {
      print('openssl: using prebuilt ${prebuilt.path}');
      outputLibName = prebuilt.uri.pathSegments.last;
      final dest = outputDir.resolve(outputLibName).toFilePath(windows: Platform.isWindows);
      await prebuilt.copy(dest);
    } else {
      final hostRequirement = compileHostRequirement(OS.current, targetOS);
      if (hostRequirement != null) {
        throw UnsupportedError(hostRequirement);
      }
      print('openssl: compiling libcrypto from source for ${targetOS.name}-${architecture.name}');
      outputLibName = await _compileFromSource(
        packageRoot: packageRoot,
        workDir: nativeOutUri(packageRoot, 'hook-build'),
        outputDir: outputDir,
        targetOS: targetOS,
        architecture: architecture,
        libName: libName,
        iosSdk: iosSdk,
      );
    }

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'src/third_party/openssl.g.dart',
        linkMode: outputLibName.linkMode,
        file: outputDir.resolve(outputLibName),
      ),
    );
  });
}

Future<String> _compileFromSource({
  required Uri packageRoot,
  required Uri workDir,
  required Uri outputDir,
  required OS targetOS,
  required Architecture architecture,
  required String libName,
  required IOSSdk? iosSdk,
}) async {
  Directory.fromUri(workDir).createSync(recursive: true);

  final openSslDir = await ensureOpenSslSource(
    packageRoot: packageRoot,
    workDir: workDir,
    runProcess: _runProcess,
  );

  final configName = resolveConfigName(targetOS, architecture, iosSdk);
  final configArgs = configureArgsFor(targetOS);

  if (targetOS == OS.android) {
    final ndkRoot = await resolveAndroidNdkRoot();
    environment['ANDROID_NDK_ROOT'] = ndkRoot;
    environment['ANDROID_NDK_HOME'] = ndkRoot;
    final toolchainBin = resolveAndroidToolchainBinDir(ndkRoot);
    final existingPath = Platform.environment['PATH'] ?? '';
    final pathSeparator = Platform.isWindows ? ';' : ':';
    environment['PATH'] = '$toolchainBin$pathSeparator$existingPath';
  }

  if (usesMsvcBuild(targetOS)) {
    await _buildWithMsvc(
      openSslDir: Uri.directory(openSslDir.path),
      configName: configName,
      configArgs: configArgs,
      workDir: workDir,
      architecture: architecture,
    );
  } else if (usesUnixMakefileBuild(targetOS)) {
    await _buildWithMake(
      openSslDir: Uri.directory(openSslDir.path),
      configName: configName,
      configArgs: configArgs,
    );
  } else {
    throw UnsupportedError('Unsupported target OS: ${targetOS.name}');
  }

  final built = File('${openSslDir.path}/$libName');
  if (!built.existsSync()) {
    final alt = _findBuiltArtifact(openSslDir, libName);
    if (alt == null) {
      throw StateError('Expected $libName under ${openSslDir.path}');
    }
    final dest = outputDir.resolve(alt.uri.pathSegments.last).toFilePath(windows: Platform.isWindows);
    await alt.copy(dest);
    return alt.uri.pathSegments.last;
  }

  final dest = outputDir.resolve(libName).toFilePath(windows: Platform.isWindows);
  await built.copy(dest);
  return libName;
}

File? _findBuiltArtifact(Directory openSslDir, String libName) {
  final pattern = libName.contains('.dll') ? 'libcrypto' : libName;
  for (final f in openSslDir.listSync()) {
    if (f is! File) continue;
    if (f.path.contains(pattern)) return f;
  }
  return null;
}

Future<void> _buildWithMsvc({
  required Uri openSslDir,
  required String configName,
  required List<String> configArgs,
  required Uri workDir,
  required Architecture architecture,
}) async {
  if (OS.current != OS.windows) {
    throw UnsupportedError('MSVC OpenSSL build must run on a Windows host.');
  }

  final msvcEnv = await resolveWindowsBuildEnvironment(architecture);
  final needDownloadPerl = !await isProgramInstalled('perl');
  final needDownloadJom = !await isProgramInstalled('jom');
  var perlProgram = 'perl';
  var jomProgram = 'jom';

  if (needDownloadPerl) {
    final perlUrl = _isWindowsArm64Host ? perlDownloadUrlModern : perlDownloadUrlLegacy;
    await downloadAndExtract(perlUrl, 'perl.zip', workDir);
    perlProgram = workDir.resolve('./perl/perl/bin/perl.exe').toFilePath(windows: true);
  }
  if (!File(perlProgram).existsSync()) {
    throw StateError('perl not found at $perlProgram after bootstrap');
  }
  print('openssl: using perl at $perlProgram');
  if (needDownloadJom) {
    await downloadAndExtract(jomDownloadUrl, 'jom.zip', workDir);
    jomProgram = workDir.resolve('./jom/jom.exe').toFilePath(windows: true);
  }

  await _runProcess(
    perlProgram,
    ['Configure', configName, ...configArgs, '/FS'],
    cwd: openSslDir,
    extraEnvironment: msvcEnv,
  );

  await _runProcess(
    jomProgram,
    ['-j', '${Platform.numberOfProcessors}'],
    cwd: openSslDir,
    extraEnvironment: msvcEnv,
  );

  if (needDownloadPerl) {
    await Directory(workDir.resolve('perl').toFilePath(windows: true)).delete(recursive: true);
  }
  if (needDownloadJom) {
    await Directory(workDir.resolve('jom').toFilePath(windows: true)).delete(recursive: true);
  }
}

Future<void> _buildWithMake({
  required Uri openSslDir,
  required String configName,
  required List<String> configArgs,
}) async {
  if (!await isProgramInstalled('perl')) {
    throw Exception('perl is not installed. Install perl to build OpenSSL from source.');
  }

  await _runProcess('./Configure', [configName, ...configArgs], cwd: openSslDir);
  await _runProcess('make', ['-j', '${Platform.numberOfProcessors}'], cwd: openSslDir);
}

bool get _isWindowsArm64Host {
  final arch = Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '';
  return Platform.isWindows && arch.toUpperCase().contains('ARM64');
}

extension on String {
  LinkMode get linkMode {
    if (endsWith('.dylib') || endsWith('.so') || endsWith('.dll')) {
      return DynamicLoadingBundled();
    }
    return StaticLinking();
  }
}

Future<Map<String, String>> resolveWindowsBuildEnvironment(Architecture architecture) async {
  final installationPath = await _findVisualStudioInstallPath();
  final vcvarsNames = switch (architecture) {
    Architecture.arm64 => ['vcvarsamd64_arm64.bat', 'vcvarsarm64.bat', 'vcvars64.bat'],
    Architecture.ia32 => ['vcvars32.bat', 'vcvars64.bat'],
    _ => ['vcvars64.bat'],
  };
  String? vcvarsPath;
  for (final name in vcvarsNames) {
    final candidate = '$installationPath\\VC\\Auxiliary\\Build\\$name';
    if (File(candidate).existsSync()) {
      vcvarsPath = candidate;
      break;
    }
  }
  if (vcvarsPath == null) {
    throw StateError('Visual Studio vcvars script not found under $installationPath');
  }

  final processResult = await Process.run(
    'cmd.exe',
    ['/c', 'call', vcvarsPath, '>nul', '&&', 'set'],
    includeParentEnvironment: true,
  );
  if (processResult.exitCode != 0) {
    throw ProcessException(
      'cmd.exe',
      ['/c', 'call', vcvarsPath, '>nul', '&&', 'set'],
      processResult.stderr,
      processResult.exitCode,
    );
  }
  final result = processResult.stdout as String;

  return Map.fromEntries(
    result.trim().split('\n').map((line) {
      final parts = line.split('=');
      if (parts.length != 2) {
        return null;
      }
      return MapEntry(parts[0].trim(), parts[1].trim());
    }).nonNulls,
  );
}

Future<String> _findVisualStudioInstallPath() async {
  final programFilesX86 = Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';
  final vswhere = '$programFilesX86\\Microsoft Visual Studio\\Installer\\vswhere.exe';
  if (File(vswhere).existsSync()) {
    final result = await Process.run(vswhere, [
      '-latest',
      '-products',
      '*',
      '-requires',
      'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
      '-property',
      'installationPath',
    ]);
    if (result.exitCode == 0) {
      final path = (result.stdout as String).trim();
      if (path.isNotEmpty && Directory(path).existsSync()) {
        return path;
      }
    }
  }

  const fallbacks = [
    r'C:\Program Files\Microsoft Visual Studio\18\Community',
    r'C:\Program Files\Microsoft Visual Studio\2022\Community',
    r'C:\Program Files\Microsoft Visual Studio\2022\Professional',
    r'C:\Program Files\Microsoft Visual Studio\2022\Enterprise',
    r'C:\Program Files\Microsoft Visual Studio\2022\BuildTools',
  ];
  for (final path in fallbacks) {
    if (Directory(path).existsSync()) {
      return path;
    }
  }

  throw StateError(
    'Visual Studio 2022 with C++ tools not found. Install MSVC or set up vswhere.',
  );
}

Future<bool> isProgramInstalled(String programName) async {
  try {
    await _runProcess(programName, []);
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> _runProcess(
  String executable,
  List<String> arguments, {
  Uri? cwd,
  Map<String, String>? extraEnvironment,
}) async {
  final processResult = await Process.run(
    executable,
    arguments,
    workingDirectory: cwd?.toFilePath(windows: Platform.isWindows),
    environment: {...?extraEnvironment, ...environment},
    includeParentEnvironment: true,
  );
  print(processResult.stdout);
  if ((processResult.stderr as String).isNotEmpty) {
    print(processResult.stderr);
  }
  if (processResult.exitCode != 0) {
    final message = StringBuffer()
      ..writeln(processResult.stdout)
      ..writeln(processResult.stderr);
    throw ProcessException(executable, arguments, message.toString(), processResult.exitCode);
  }
}

Future<void> downloadAndExtract(
  String url,
  String outputFileName,
  Uri workDir, {
  bool createFolderForExtraction = true,
}) async {
  await _runProcess('curl', ['-L', url, '-o', outputFileName], cwd: workDir);

  final isTarGz = outputFileName.endsWith('.tar.gz');
  final destinationPath = workDir.resolve(outputFileName.replaceAll('.tar.gz', '').replaceAll('.zip', ''));
  await Directory(destinationPath.toFilePath(windows: Platform.isWindows)).create(recursive: true);
  await _runProcess('tar', [
    isTarGz ? '-xzf' : '-xf',
    outputFileName,
    if (createFolderForExtraction) ...['-C', destinationPath.toFilePath(windows: Platform.isWindows)],
  ], cwd: workDir);

  await File(workDir.resolve(outputFileName).toFilePath(windows: Platform.isWindows)).delete();
}
