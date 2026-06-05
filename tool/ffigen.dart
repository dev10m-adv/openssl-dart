import 'dart:io';

import 'package:ffigen/ffigen.dart';
import 'package:logging/logging.dart';

import 'libcrypto_headers.dart';

void main() {
  final packageRoot = Platform.script.resolve('../');
  final opensslInclude = _resolveIncludeRoot(packageRoot);
  final opensslPublic = opensslInclude.resolve('openssl/');
  final logger = Logger('ffigen')..onRecord.listen((record) => print(record.message));

  final headers = <Uri>[];
  final compilerOpts = [...defaultCompilerOpts(logger), '-I${opensslInclude.toFilePath()}'];

  bool allowPublic(Declaration decl) => includeDeclaration(decl.originalName);

  final opensslPublicDir = Directory.fromUri(opensslPublic);
  for (final entry in opensslPublicDir.listSync(recursive: true)) {
    if (entry.path.endsWith('.h') && !isExcludedHeader(entry.path)) {
      headers.add(entry.uri);
    }
  }

  if (headers.isEmpty) {
    stderr.writeln(
      'No OpenSSL headers found under ${opensslPublic.path}.\n'
      'Initialize the submodule or extract openssl-3.5.4 sources.',
    );
    exit(1);
  }

  FfiGenerator(
    headers: Headers(entryPoints: headers, compilerOptions: compilerOpts),
    functions: Functions(include: allowPublic),
    macros: Macros(include: allowPublic),
    globals: Globals(include: allowPublic),
    enums: Enums(include: allowPublic),
    output: Output(dartFile: packageRoot.resolve('lib/src/third_party/openssl.g.dart')),
  ).generate(logger: logger);

  print('Run `dart run tool/trim_bindings.dart` to remove any remaining TLS/system symbols.');
}

Uri _resolveIncludeRoot(Uri packageRoot) {
  final candidates = [
    packageRoot.resolve('native/third_party/openssl/include/'),
    packageRoot.resolve('openssl_repo/include/'),
    packageRoot.resolve('openssl-3.5.4/include/'),
  ];
  for (final candidate in candidates) {
    if (Directory.fromUri(candidate).existsSync()) {
      return candidate;
    }
  }
  return candidates.first;
}
