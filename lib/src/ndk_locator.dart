import 'dart:io';

/// Returns Android NDK root when installed, else null.
String? tryResolveAndroidNdkRoot() {
  for (final key in ['ANDROID_NDK_ROOT', 'ANDROID_NDK_HOME']) {
    final value = Platform.environment[key];
    if (value != null && value.isNotEmpty && Directory(value).existsSync()) {
      return _normalizePath(value);
    }
  }

  final candidates = <String>[];

  if (Platform.isWindows) {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null) {
      candidates.addAll(_listVersionedSubdirs('$localAppData\\Android\\Sdk\\ndk'));
    }
    candidates.addAll([
      r'C:\Android\android-ndk-r27c',
      r'C:\Android\Sdk\ndk\27.0.12077973',
    ]);
  }

  if (Platform.isLinux || Platform.isMacOS) {
    final home = Platform.environment['HOME'];
    if (home != null) {
      candidates.addAll(_listVersionedSubdirs('$home/Android/Sdk/ndk'));
      candidates.addAll(_listVersionedSubdirs('$home/Library/Android/sdk/ndk'));
    }
    candidates.add('/opt/android-ndk');
  }

  for (final path in candidates) {
    if (_looksLikeNdkRoot(path)) {
      return path;
    }
  }
  return null;
}

bool hasAndroidNdkInstalled() => tryResolveAndroidNdkRoot() != null;

String ndkToolchainBinDir(String ndkRoot) {
  final hostTags = switch (Platform.operatingSystem) {
    'windows' => const ['windows-x86_64', 'windows-arm64'],
    'macos' => const ['darwin-arm64', 'darwin-x86_64'],
    'linux' => const ['linux-x86_64', 'linux-arm64'],
    final os => throw UnsupportedError('Unsupported host OS for Android NDK: $os'),
  };
  for (final host in hostTags) {
    final bin = Directory('$ndkRoot/toolchains/llvm/prebuilt/$host/bin');
    if (bin.existsSync()) return bin.path;
  }
  throw StateError('NDK toolchain bin not found under $ndkRoot');
}

List<String> _listVersionedSubdirs(String parentPath) {
  final parent = Directory(parentPath);
  if (!parent.existsSync()) return const [];

  final versions = parent
      .listSync()
      .whereType<Directory>()
      .map((d) => d.path)
      .where(_looksLikeNdkRoot)
      .toList()
    ..sort((a, b) => b.compareTo(a));
  return versions;
}

bool _looksLikeNdkRoot(String path) {
  final root = Directory(path);
  if (!root.existsSync()) return false;
  return Directory('${root.path}/toolchains/llvm/prebuilt').existsSync();
}

String _normalizePath(String path) => Directory(path).absolute.path;
