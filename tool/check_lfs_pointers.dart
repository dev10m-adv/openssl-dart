import 'dart:io';

/// Fails if any Git LFS-tracked file in [native/prebuilt/] is an unsmudged pointer.
void main() async {
  final result = await Process.run(
    'git',
    ['lfs', 'ls-files'],
    runInShell: Platform.isWindows,
  );
  if (result.exitCode != 0) {
    stderr.writeln('check_lfs_pointers: git lfs ls-files failed');
    stderr.write(result.stderr as String);
    exit(1);
  }

  final failures = <String>[];
  for (final line in (result.stdout as String).split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || !trimmed.contains('native/prebuilt/')) continue;
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length < 3) continue;
    final path = parts.sublist(2).join(' ');
    if (!_isPrebuiltBinaryPath(path)) continue;
    final file = File(path);
    if (!file.existsSync()) continue;
    if (file.lengthSync() < 4096) {
      failures.add('$path (${file.lengthSync()} bytes)');
    }
  }

  if (failures.isEmpty) {
    stdout.writeln('check_lfs_pointers: ok');
    return;
  }

  stderr.writeln('check_lfs_pointers: unsmudged LFS files:');
  for (final f in failures) {
    stderr.writeln('  $f');
  }
  exit(1);
}

bool _isPrebuiltBinaryPath(String path) {
  final name = path.split('/').last;
  if (name == '.build-hash' ||
      name == 'manifest.json' ||
      name == 'manifest.json.sig' ||
      name == 'README.md') {
    return false;
  }
  if (name.contains('libcrypto')) return true;
  if (name.endsWith('.xcframework')) return true;
  return false;
}
