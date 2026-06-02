import 'dart:io';

/// Prints instructions for populating [prebuilt/] on the current host (Git LFS).
///
/// Full automation requires running a Flutter/Dart app build per target triple
/// so the openssl hook compiles and copies output into [prebuilt/].
void main() {
  stdout.writeln('Prebuilt layout: prebuilt/$openSslVersion/<triple>/<libcrypto>');
  stdout.writeln('');
  stdout.writeln('On this host (${Platform.operatingSystem}), build the package tests to produce libcrypto:');
  stdout.writeln('  dart test');
  stdout.writeln('');
  stdout.writeln('Then copy the native asset from .dart_tool/hooks_runner/ into prebuilt/<triple>/.');
  stdout.writeln('Run `dart run tool/verify_prebuilts.dart` then commit (`git lfs` uploads on push).');
  stdout.writeln('CI: .github/workflows/prebuilts.yml (workflow_dispatch or release).');
  stdout.writeln('Note: prebuilt/ is not published to pub.dev (see .pubignore).');
}

const openSslVersion = '3.5.4';
