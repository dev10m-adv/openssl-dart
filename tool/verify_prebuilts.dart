import 'dart:convert';
import 'dart:io';

import 'package:openssl/src/native_version.dart';
import 'package:openssl/src/prebuilt_attestation.dart';
import 'package:openssl/src/prebuilt_paths.dart';

/// Fails if required [native/prebuilt/<version>/] artifacts are missing or LFS pointers.
///
/// `--allow-partial`: skip missing triple directories (for PRs that do not ship full matrix).
/// `--require-signature`: require valid [manifest.json.sig] when public key is present.
void main(List<String> args) async {
  final allowPartial = args.contains('--allow-partial');
  final requireSignature = args.contains('--require-signature');
  final packageRoot = Directory.current.uri;
  final version = readOpenSslVersion(packageRoot);
  final versionRoot = Directory.fromUri(prebuiltVersionRootUri(packageRoot));
  if (!versionRoot.existsSync()) {
    if (allowPartial) {
      stdout.writeln('verify_prebuilts: no $prebuiltRoot/$version/ (partial ok)');
      return;
    }
    stderr.writeln('verify_prebuilts: missing $prebuiltRoot/$version/');
    exit(1);
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
    return;
  }

  stderr.writeln('verify_prebuilts: failed:');
  for (final line in failures) {
    stderr.writeln('  $line');
  }
  exit(1);
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
