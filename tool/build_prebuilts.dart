import 'dart:io';

/// Prints instructions for populating [prebuilt/] on the current host.
///
/// Full automation requires running a Flutter/Dart app build per target triple
/// so the openssl hook compiles and copies output into [prebuilt/].
void main() {
  stdout.writeln('Prebuilt layout: prebuilt/$openSslVersion/<triple>/<libcrypto>');
  stdout.writeln('');
  stdout.writeln('On this host (${Platform.operatingSystem}), build the package tests to produce libcrypto:');
  stdout.writeln('  dart test');
  stdout.writeln('');
  stdout.writeln('Then copy the native asset from .dart_tool/hooks_runner/openssl/ into prebuilt/.');
  stdout.writeln('CI workflow .github/workflows/prebuilts.yml automates this on release tags.');
}

const openSslVersion = '3.5.4';
