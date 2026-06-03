import 'dart:io';

import 'package:openssl/src/native_version.dart';
import 'package:openssl/src/prebuilt_paths.dart';

/// Prints how to populate [native/prebuilt/] on the current host.
void main() {
  final packageRoot = Directory.current.uri;
  final version = readOpenSslVersion(packageRoot);
  stdout.writeln('Prebuilt layout: $prebuiltRoot/$version/<platform-dir>/libcrypto.*');
  stdout.writeln('Required triples: ${requiredPrebuiltTriples.join(', ')}');
  stdout.writeln('');
  stdout.writeln('Build one triple (example):');
  stdout.writeln('  TRIPLE=linux-x64 bash native/build/linux.sh');
  stdout.writeln('  pwsh native/build/windows.ps1 -Triple windows-arm64');
  stdout.writeln('');
  stdout.writeln('Then: dart run tool/verify_prebuilts.dart');
  stdout.writeln('Hash:  dart run tool/compute_build_hash.dart');
  stdout.writeln('CI:    .github/workflows/prebuilts.yml');
}
