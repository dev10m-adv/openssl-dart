import 'dart:convert';
import 'dart:io';

import 'package:openssl/src/native_version.dart';
import 'package:openssl/src/prebuilt_paths.dart';

/// Syncs [native/prebuilt/manifest.json] index from [native/src/VERSION].
///
/// Prefer [tool/sign_prebuilts.dart] for version manifests and SHA-256.
/// `--check`: exit 1 if manifest would change (CI).
void main(List<String> args) {
  final checkOnly = args.contains('--check');
  final packageRoot = Directory.current.uri;
  final version = readOpenSslVersion(packageRoot);
  final manifestFile = File.fromUri(prebuiltManifestUri(packageRoot));

  final expected = <String, dynamic>{
    'activeVersion': version,
    'triples': requiredPrebuiltTriples,
  };
  const encoder = JsonEncoder.withIndent('  ');
  final expectedBody = '${encoder.convert(expected)}\n';

  final current = manifestFile.existsSync() ? manifestFile.readAsStringSync() : '';
  if (current == expectedBody) {
    stdout.writeln('sync_manifest: ok');
    return;
  }

  if (checkOnly) {
    stderr.writeln('sync_manifest: manifest.json out of date; run `dart run tool/sync_manifest.dart`');
    stderr.writeln('--- expected ---');
    stderr.write(expectedBody);
    exit(1);
  }

  manifestFile.parent.createSync(recursive: true);
  manifestFile.writeAsStringSync(expectedBody);
  stdout.writeln('sync_manifest: wrote ${manifestFile.path}');
}
