import 'dart:convert';
import 'dart:io';

import 'native_version.dart';
import 'prebuilt_attestation.dart';
import 'prebuilt_paths.dart';

/// Verifies [native/prebuilt/] artifacts under [packageRoot].
///
/// Returns exit code 0 on success, 1 on failure.
/// See [bin/verify_prebuilts.dart] and `dart run tool/verify_prebuilts.dart`.
Future<int> verifyPrebuilts(
  Uri packageRoot, {
  bool allowPartial = false,
  bool requireSignature = false,
}) async {
  final version = readOpenSslVersion(packageRoot);
  final versionRoot = Directory.fromUri(prebuiltVersionRootUri(packageRoot));
  if (!versionRoot.existsSync()) {
    if (allowPartial) {
      stdout.writeln('verify_prebuilts: no $prebuiltRoot/$version/ (partial ok)');
      return 0;
    }
    stderr.writeln('verify_prebuilts: missing $prebuiltRoot/$version/');
    return 1;
  }

  final failures = <String>[];
  _rejectLegacyFlatLayout(packageRoot, failures);
  _verifyRootIndex(packageRoot, version, failures);

  final manifestFile = File.fromUri(versionManifestUri(packageRoot));
  if (manifestFile.existsSync()) {
    final sigFile = File.fromUri(versionManifestSigUri(packageRoot));
    if (requireSignature && !sigFile.existsSync()) {
      failures.add('${sigFile.path} missing (--require-signature)');
    }
    final sigError = await verifyManifestSignature(packageRoot);
    if (sigError != null) {
      if (requireSignature) {
        failures.add(sigError);
      } else {
        stdout.writeln('verify_prebuilts: warning: $sigError');
      }
    }
  } else if (!allowPartial) {
    failures.add('${manifestFile.path} missing (run dart run tool/sign_prebuilts.dart)');
  }

  if (!allowPartial) {
    final hashFile = File.fromUri(buildHashFileUri(packageRoot));
    if (!hashFile.existsSync()) {
      failures.add('${hashFile.path} missing (run prebuilts CI or compute_build_hash)');
    }
  }

  for (final triple in requiredPrebuiltTriples) {
    final dir = Directory.fromUri(prebuiltDirUri(packageRoot, triple));
    if (!dir.existsSync()) {
      if (allowPartial || optionalPrebuiltTriples.contains(triple)) {
        final reason =
            optionalPrebuiltTriples.contains(triple) ? 'optional' : 'partial';
        stdout.writeln('verify_prebuilts: skip missing $version/$triple/ ($reason)');
        continue;
      }
      failures.add('$version/$triple/ missing');
      continue;
    }
    if (triple == 'ios-xcframework') {
      await _verifyIosXcframework(packageRoot, dir, failures, version, triple, manifestFile.existsSync());
      continue;
    }
    await _verifySharedLibrary(packageRoot, dir, failures, version, triple, manifestFile.existsSync());
  }

  if (manifestFile.existsSync()) {
    final onDisk = collectVersionArtifacts(versionRoot);
    final manifest = readVersionManifest(packageRoot);
    final listed = (manifest['artifacts'] as Map<String, dynamic>?) ?? {};
    for (final path in listed.keys) {
      if (!onDisk.containsKey(path)) {
        if (!allowPartial) {
          failures.add('manifest lists $path but file missing on disk');
        }
      }
    }
  }

  for (final entity in versionRoot.listSync(recursive: true)) {
    if (entity is! File) continue;
    final relative = entity.path
        .substring(versionRoot.path.length)
        .replaceAll(r'\', '/')
        .replaceFirst(RegExp(r'^/'), '');
    if (!isPrebuiltBinaryArtifactPath(relative)) continue;
    if (entity.lengthSync() < 4096) {
      failures.add('${entity.path} (${entity.lengthSync()} bytes — run `git lfs pull`)');
    }
  }

  if (failures.isEmpty) {
    stdout.writeln('verify_prebuilts: ok (OpenSSL $version${allowPartial ? ', partial' : ''})');
    return 0;
  }

  stderr.writeln('verify_prebuilts: failed:');
  for (final line in failures) {
    stderr.writeln('  $line');
  }
  return 1;
}

void _rejectLegacyFlatLayout(Uri packageRoot, List<String> failures) {
  final prebuiltRootDir = Directory.fromUri(packageRoot.resolve(prebuiltRoot));
  if (!prebuiltRootDir.existsSync()) return;
  for (final triple in requiredPrebuiltTriples) {
    final legacy = Directory('${prebuiltRootDir.path}/$triple');
    if (legacy.existsSync()) {
      failures.add(
        'legacy layout $prebuiltRoot/$triple/ — remove; use $prebuiltRoot/<version>/$triple/',
      );
    }
  }
}

void _verifyRootIndex(Uri packageRoot, String version, List<String> failures) {
  final indexFile = File.fromUri(prebuiltManifestUri(packageRoot));
  if (!indexFile.existsSync()) {
    failures.add('native/prebuilt/manifest.json (index) missing');
    return;
  }
  try {
    final json = jsonDecode(indexFile.readAsStringSync()) as Map<String, dynamic>;
    if (json['activeVersion'] != version) {
      failures.add('index activeVersion != $version');
    }
  } on FormatException catch (e) {
    failures.add('index manifest invalid: $e');
  }
}

Future<void> _verifyIosXcframework(
  Uri packageRoot,
  Directory dir,
  List<String> failures,
  String version,
  String triple,
  bool hasManifest,
) async {
  final xc = Directory('${dir.path}/OpenSSL.xcframework');
  if (!xc.existsSync()) {
    failures.add('$version/$triple/OpenSSL.xcframework missing');
    return;
  }
  var foundArtifact = false;
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File) continue;
    if (entity.path.endsWith('libcrypto.a') || entity.path.endsWith('libcrypto.dylib')) {
      if (entity.lengthSync() >= 4096) {
        foundArtifact = true;
        if (hasManifest) {
          final err = await verifyPrebuiltArtifact(packageRoot: packageRoot, artifactFile: entity);
          if (err != null) failures.add(err);
        }
      }
    }
  }
  if (!foundArtifact) {
    failures.add('$version/$triple: no libcrypto artifact found');
  }
}

Future<void> _verifySharedLibrary(
  Uri packageRoot,
  Directory dir,
  List<String> failures,
  String version,
  String triple,
  bool hasManifest,
) async {
  var ok = false;
  for (final entity in dir.listSync()) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    if (isLibcryptoLibraryFileName(name)) {
      if (entity.lengthSync() >= 4096) {
        ok = true;
        if (hasManifest) {
          final err = await verifyPrebuiltArtifact(packageRoot: packageRoot, artifactFile: entity);
          if (err != null) failures.add(err);
        }
      }
    }
  }
  if (!ok) {
    failures.add('$version/$triple/: expected libcrypto shared library');
  }
}
