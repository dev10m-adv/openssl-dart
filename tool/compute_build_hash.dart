import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:code_assets/code_assets.dart';
import 'package:openssl/src/build_target.dart';
import 'package:openssl/src/native_version.dart';
import 'package:openssl/src/prebuilt_paths.dart';

/// Prints a stable sha256 hash of native build inputs (for [native/prebuilt/<version>/.build-hash]).
void main(List<String> args) {
  final packageRoot = Directory.current.uri;
  final version = readOpenSslVersion(packageRoot);
  final digest = sha256ForNativeBuild(packageRoot);
  final line = 'sha256:$digest';
  stdout.writeln(line);

  final writePath = args.isNotEmpty
      ? args.first
      : File.fromUri(buildHashFileUri(packageRoot)).path;
  File(writePath).writeAsStringSync('$line\n');
  stderr.writeln('Wrote $writePath (OpenSSL $version)');
}

String sha256ForNativeBuild(Uri packageRoot) {
  final sink = Accumulator();
  _hashTree(sink, Directory.fromUri(packageRoot.resolve('native/build/')), {'.md'});
  _hashTree(sink, Directory.fromUri(packageRoot.resolve('native/src/')), {'.md'});
  _hashFile(sink, File.fromUri(packageRoot.resolve('native/src/VERSION')));
  _hashFile(sink, File.fromUri(packageRoot.resolve('lib/src/build_target.dart')));
  _hashFile(sink, File.fromUri(packageRoot.resolve('lib/src/native_version.dart')));
  _hashFile(sink, File.fromUri(packageRoot.resolve('lib/src/prebuilt_paths.dart')));

  final opensslSubmodule = Directory.fromUri(packageRoot.resolve('native/third_party/openssl/'));
  if (opensslSubmodule.existsSync()) {
    final head = File('${opensslSubmodule.path}/.git');
    if (head.existsSync()) {
      sink.add('submodule:${head.readAsStringSync().trim()}');
    }
  }

  final version = readOpenSslVersion(packageRoot);
  sink.add('version:$version');
  for (final os in [OS.linux, OS.windows, OS.macOS, OS.android, OS.iOS]) {
    sink.add('configure:${os.name}:${configureArgsFor(os).join(",")}');
  }

  return sink.digest;
}

void _hashTree(Accumulator sink, Directory dir, Set<String> excludeSuffix) {
  if (!dir.existsSync()) return;
  final files = <File>[];
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    if (name.startsWith('.')) continue;
    if (excludeSuffix.any(name.endsWith)) continue;
    files.add(entity);
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    _hashFile(sink, file);
  }
}

void _hashFile(Accumulator sink, File file) {
  if (!file.existsSync()) return;
  final relative = file.path.replaceAll(r'\', '/');
  sink.add(relative);
  sink.add(base64Encode(sha256.convert(file.readAsBytesSync()).bytes));
}

class Accumulator {
  final _parts = <String>[];

  void add(String part) => _parts.add(part);

  String get digest => sha256.convert(utf8.encode(_parts.join('\n'))).toString();
}
