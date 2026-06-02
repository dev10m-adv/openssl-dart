import 'dart:io';

/// Fails if any file under [prebuilt/] looks like an unsmudged Git LFS pointer.
void main() {
  final packageRoot = Directory.current.uri;
  final prebuiltDir = Directory.fromUri(packageRoot.resolve('prebuilt/'));
  if (!prebuiltDir.existsSync()) {
    stdout.writeln('verify_prebuilts: no prebuilt/ directory (ok)');
    return;
  }

  final failures = <String>[];
  for (final entity in prebuiltDir.listSync(recursive: true)) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    if (name.endsWith('.md')) continue;
    final size = entity.lengthSync();
    if (size < 4096) {
      failures.add('${entity.path} ($size bytes — likely Git LFS pointer; run `git lfs pull`)');
    }
  }

  if (failures.isEmpty) {
    stdout.writeln('verify_prebuilts: ok');
    return;
  }

  stderr.writeln('verify_prebuilts: failed:');
  for (final line in failures) {
    stderr.writeln('  $line');
  }
  exit(1);
}
