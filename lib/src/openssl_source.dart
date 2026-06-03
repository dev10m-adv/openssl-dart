import 'dart:io';

import 'native_version.dart';
import 'prebuilt_paths.dart';

String _tarballName(Uri packageRoot) => 'openssl-${readOpenSslVersion(packageRoot)}.tar.gz';

String _sourceCodeUrl(Uri packageRoot) {
  final version = readOpenSslVersion(packageRoot);
  return 'https://github.com/openssl/openssl/releases/download/openssl-$version/openssl-$version.tar.gz';
}

/// OpenSSL source tree for Configure/make (submodule preferred).
Future<Directory> ensureOpenSslSource({
  required Uri packageRoot,
  required Uri workDir,
  required Future<void> Function(String exe, List<String> args, {Uri? cwd}) runProcess,
}) async {
  final version = readOpenSslVersion(packageRoot);
  final submodule = Directory.fromUri(nativeThirdPartyOpenSsl(packageRoot));
  if (submodule.existsSync() && _looksLikeOpenSslTree(submodule)) {
    return submodule;
  }

  final extracted = Directory.fromUri(workDir.resolve('openssl-$version/'));
  if (extracted.existsSync() && _looksLikeOpenSslTree(extracted)) {
    return extracted;
  }

  final tarballName = _tarballName(packageRoot);
  final tarball = File.fromUri(workDir.resolve(tarballName));
  if (!tarball.existsSync()) {
    await runProcess('curl', ['-L', _sourceCodeUrl(packageRoot), '-o', tarballName], cwd: workDir);
  }

  await runProcess('tar', ['-xzf', tarballName], cwd: workDir);

  final extractedPath = '${workDir.toFilePath()}openssl-$version';
  final tree = Directory(extractedPath);
  if (!_looksLikeOpenSslTree(tree)) {
    throw StateError('OpenSSL source not found under $extractedPath');
  }
  return tree;
}

bool _looksLikeOpenSslTree(Directory dir) =>
    File('${dir.path}/Configure').existsSync() || File('${dir.path}/config').existsSync();
