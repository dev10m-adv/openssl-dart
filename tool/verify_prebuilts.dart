import 'dart:convert';
import 'dart:io';

import 'package:openssl/src/native_version.dart';
import 'package:openssl/src/prebuilt_paths.dart';

/// Fails if required [native/prebuilt/<version>/] artifacts are missing or LFS pointers.
///
/// `--allow-partial`: skip missing triple directories (for PRs that do not ship full matrix).
void main(List<String> args) {
  final allowPartial = args.contains('--allow-partial');
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
  _verifyManifest(packageRoot, version, failures);

  if (!allowPartial) {
    final hashFile = File.fromUri(buildHashFileUri(packageRoot));
    if (!hashFile.existsSync()) {
      failures.add('${hashFile.path} missing (run prebuilts CI or compute_build_hash)');
    }
  }

  for (final triple in requiredPrebuiltTriples) {
    final dir = Directory.fromUri(prebuiltDirUri(packageRoot, triple));
    if (!dir.existsSync()) {
      if (allowPartial) {
        stdout.writeln('verify_prebuilts: skip missing $version/$triple/ (partial)');
        continue;
      }
      failures.add('$version/$triple/ missing');
      continue;
    }
    if (triple == 'ios-xcframework') {
      _verifyIosXcframework(dir, failures, version, triple);
      continue;
    }
    _verifySharedLibrary(dir, failures, version, triple);
  }

  for (final entity in versionRoot.listSync(recursive: true)) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    if (name == '.build-hash' || name.endsWith('.md')) continue;
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

void _verifyManifest(Uri packageRoot, String version, List<String> failures) {
  final manifestFile = File.fromUri(prebuiltManifestUri(packageRoot));
  if (!manifestFile.existsSync()) {
    failures.add('native/prebuilt/manifest.json missing');
    return;
  }
  try {
    final json = jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    final active = json['activeVersion'] as String?;
    if (active != version) {
      failures.add('manifest activeVersion=$active does not match native/src/VERSION=$version');
    }
    final triples = (json['triples'] as List<dynamic>?)?.cast<String>() ?? [];
    for (final required in requiredPrebuiltTriples) {
      if (!triples.contains(required)) {
        failures.add('manifest.json missing triple $required');
      }
    }
  } on FormatException catch (e) {
    failures.add('manifest.json invalid: $e');
  }
}

void _verifyIosXcframework(Directory dir, List<String> failures, String version, String triple) {
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
      }
    }
  }
  if (!foundArtifact) {
    failures.add('$version/$triple: no libcrypto artifact found');
  }
}

void _verifySharedLibrary(Directory dir, List<String> failures, String version, String triple) {
  final patterns = switch (triple) {
    'windows-x64' || 'windows-arm64' => ['libcrypto', '.dll'],
    'macos-universal' => ['libcrypto', '.dylib'],
    _ => ['libcrypto', '.so'],
  };
  var ok = false;
  for (final entity in dir.listSync()) {
    if (entity is! File) continue;
    if (entity.path.contains(patterns[0]) && entity.path.endsWith(patterns[1])) {
      if (entity.lengthSync() >= 4096) {
        ok = true;
      }
    }
  }
  if (!ok) {
    failures.add('$version/$triple/: expected libcrypto shared library');
  }
}
