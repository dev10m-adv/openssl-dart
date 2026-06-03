import 'dart:io';

import 'package:openssl/src/package_locator.dart';
import 'package:test/test.dart';

void main() {
  test('locateOpenSslPackageRoot finds package when cwd is openssl repo', () async {
    final root = await locateOpenSslPackageRoot();
    expect(root.path, contains('openssl'));
  });

  test('locateOpenSslPackageRoot prefers package_config over pub cache', () async {
    final config = File('.dart_tool/package_config.json');
    if (!config.existsSync()) {
      return;
    }
    final root = await locateOpenSslPackageRoot();
    final content = config.readAsStringSync();
    if (content.contains('advforks/openssl_dart') || content.contains('openssl_dart')) {
      expect(root.path.toLowerCase(), contains('openssl_dart'));
    }
  });
}
