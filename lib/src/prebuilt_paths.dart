import 'dart:io';

import 'package:code_assets/code_assets.dart';

import 'build_target.dart';
import 'native_version.dart';
import 'prebuilt_attestation.dart';

/// Root of committed prebuilt artifacts (Git LFS).
const prebuiltRoot = 'native/prebuilt';

/// Platform folders CI is expected to populate (dynamic libcrypto only).
const requiredPrebuiltTriples = [
  'android-arm64-v8a',
  'android-x86_64',
  'ios-xcframework',
  'macos-universal',
  'windows-x64',
  'windows-arm64',
  'linux-x64',
  'linux-arm64',
];

/// Built when CI has a suitable runner; strict verify skips if absent.
const optionalPrebuiltTriples = ['windows-arm64'];

/// `native/prebuilt/<version>/`
Uri prebuiltVersionRootUri(Uri packageRoot) {
  final version = readOpenSslVersion(packageRoot);
  return packageRoot.resolve('$prebuiltRoot/$version/');
}

/// Maps a code-asset target to a platform subdirectory under the versioned prebuilt root.
String? resolvePrebuiltPlatformDir({
  required OS targetOS,
  required Architecture architecture,
  required LinkModePreference linkMode,
}) {
  final preferStatic =
      linkMode == LinkModePreference.static || linkMode == LinkModePreference.preferStatic;
  if (preferStatic) {
    return null;
  }
  return switch ((targetOS, architecture)) {
    (OS.android, Architecture.arm64) => 'android-arm64-v8a',
    (OS.android, Architecture.x64) => 'android-x86_64',
    (OS.iOS, _) => 'ios-xcframework',
    (OS.macOS, _) => 'macos-universal',
    (OS.windows, Architecture.x64) => 'windows-x64',
    (OS.windows, Architecture.arm64) => 'windows-arm64',
    (OS.linux, Architecture.x64) => 'linux-x64',
    (OS.linux, Architecture.arm64) => 'linux-arm64',
    _ => null,
  };
}

/// Resolves the libcrypto file under [native/prebuilt/<version>/], if present and smudged.
File? resolvePrebuiltArtifact({
  required Uri packageRoot,
  required OS targetOS,
  required Architecture architecture,
  required LinkModePreference linkMode,
  IOSSdk? iosSdk,
}) {
  final platformDir = resolvePrebuiltPlatformDir(
    targetOS: targetOS,
    architecture: architecture,
    linkMode: linkMode,
  );
  if (platformDir == null) {
    return null;
  }

  final prebuiltDir = Directory.fromUri(prebuiltDirUri(packageRoot, platformDir));
  if (!prebuiltDir.existsSync()) {
    return null;
  }

  if (targetOS == OS.iOS) {
    return _resolveIosPrebuilt(prebuiltDir, iosSdk);
  }

  final libName = resolveLibFileName(targetOS, architecture, linkMode);
  final exact = File('${prebuiltDir.path}/$libName');
  if (exact.existsSync()) {
    return _acceptPrebuiltFile(exact);
  }
  for (final entity in prebuiltDir.listSync()) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    if (isLibcryptoLibraryFileName(name)) {
      return _acceptPrebuiltFile(entity);
    }
  }
  return null;
}

File? _resolveIosPrebuilt(Directory prebuiltDir, IOSSdk? iosSdk) {
  final isSimulator = iosSdk == IOSSdk.iPhoneSimulator;
  File? fallback;

  for (final entity in prebuiltDir.listSync(recursive: true)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('libcrypto.dylib') && !entity.path.endsWith('libcrypto.a')) {
      continue;
    }
    final accepted = _acceptPrebuiltFile(entity);
    if (accepted == null) continue;

    final pathLower = entity.path.toLowerCase();
    if (isSimulator) {
      if (pathLower.contains('simulator') || pathLower.contains('iphonesimulator')) {
        return accepted;
      }
    } else {
      if (!pathLower.contains('simulator') && !pathLower.contains('iphonesimulator')) {
        return accepted;
      }
    }
    fallback ??= accepted;
  }

  return fallback;
}

File? _acceptPrebuiltFile(File candidate) {
  if (!candidate.existsSync()) {
    return null;
  }
  if (candidate.lengthSync() < 4096) {
    return null;
  }
  return candidate;
}

Uri prebuiltDirUri(Uri packageRoot, String platformDir) {
  final version = readOpenSslVersion(packageRoot);
  return packageRoot.resolve('$prebuiltRoot/$version/$platformDir/');
}

Uri nativeOutUri(Uri packageRoot, String triple) {
  final version = readOpenSslVersion(packageRoot);
  return packageRoot.resolve('native/out/$version/$triple/');
}

Uri nativeThirdPartyOpenSsl(Uri packageRoot) =>
    packageRoot.resolve('native/third_party/openssl/');

Uri buildHashFileUri(Uri packageRoot) {
  final version = readOpenSslVersion(packageRoot);
  return packageRoot.resolve('$prebuiltRoot/$version/.build-hash');
}

Uri prebuiltManifestUri(Uri packageRoot) =>
    packageRoot.resolve('$prebuiltRoot/manifest.json');
