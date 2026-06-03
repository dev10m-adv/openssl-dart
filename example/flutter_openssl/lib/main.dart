import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:openssl/crypto.dart';

void main() {
  runApp(const OpenSslDemoApp());
}

class OpenSslDemoApp extends StatelessWidget {
  const OpenSslDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'openssl example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final String _version = openSslLibcryptoVersion();
  String _status = 'Tap Run to exercise AES-256-CBC via libcrypto.';
  String? _cipherB64;
  bool _busy = false;

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _status = 'Running…';
      _cipherB64 = null;
    });
    try {
      final cipher = await compute((_) => _smokeTest(), null);
      setState(() {
        _status = 'OK on ${defaultTargetPlatform.name} · OpenSSL $_version';
        _cipherB64 = cipher;
      });
    } catch (e, st) {
      setState(() => _status = 'Failed: $e');
      debugPrintStack(stackTrace: st);
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('openssl $_version')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Platform: ${defaultTargetPlatform.name}'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _run,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Run AES round-trip'),
            ),
            const SizedBox(height: 16),
            Text(_status),
            if (_cipherB64 != null) SelectableText('b64: $_cipherB64'),
          ],
        ),
      ),
    );
  }
}

String _smokeTest() {
  const message = 'Hello from OpenSSL libcrypto';
  final key = Uint8List.fromList(utf8.encode('Nc92PMoPjcIls5QoXeki5yIPuhjjWMcx'));
  final iv = Uint8List.fromList(utf8.encode('1234567890123456'));
  final plain = Uint8List.fromList(utf8.encode(message));
  final enc = aes256Cbc(plain, key, iv, encrypt: true);
  final dec = aes256Cbc(enc, key, iv, encrypt: false);
  if (utf8.decode(dec) != message) throw StateError('roundtrip failed');
  // Also exercise digest + CSPRNG helpers.
  final sha = toHex(sha256(plain));
  final nonce = toHex(randomBytes(8));
  return 'aes=${base64.encode(enc)}\nsha256=$sha\nrand=$nonce';
}
