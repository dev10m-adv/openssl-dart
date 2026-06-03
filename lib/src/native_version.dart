import 'dart:io';

const _versionPath = 'native/src/VERSION';

/// OpenSSL version pin from [native/src/VERSION] at the package root.
String readOpenSslVersion([Uri? packageRoot]) {
  final file = packageRoot == null
      ? File(_versionPath)
      : File.fromUri(packageRoot.resolve(_versionPath));
  if (!file.existsSync()) {
    throw StateError('Missing ${file.path}; create native/src/VERSION');
  }
  return file.readAsStringSync().trim();
}

/// Same as [readOpenSslVersion] when the current working directory is the package root.
String get openSslVersion => readOpenSslVersion();
