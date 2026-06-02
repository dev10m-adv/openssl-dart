import 'package:flutter/material.dart';
import 'package:openssl/openssl.dart' as openssl;

void main() {
  runApp(const OpenSslDemoApp());
}

class OpenSslDemoApp extends StatelessWidget {
  const OpenSslDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final version =
        '${openssl.OPENSSL_version_major()}.${openssl.OPENSSL_version_minor()}.${openssl.OPENSSL_version_patch()}';
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('openssl libcrypto')),
        body: Center(
          child: Text('OpenSSL libcrypto $version'),
        ),
      ),
    );
  }
}
