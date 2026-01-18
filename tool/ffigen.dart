import 'dart:io';

import 'package:ffigen/ffigen.dart';
import 'package:logging/logging.dart';

void main() {
  final packageRoot = Platform.script.resolve('../');
  final opensslInclude = packageRoot.resolve('openssl_repo/include/');
  // Only expose the public OpenSSL headers; internal crypto headers (e.g.
  // crypto/md32_common.h) expect algorithm-specific macros and fail if parsed
  // standalone.
  final opensslPublic = opensslInclude.resolve('openssl/');
  final logger = Logger('ffigen')..onRecord.listen((record) => print(record.message));

  final headers = <Uri>[];
  final compilerOpts = [...defaultCompilerOpts(logger), '-I${opensslInclude.toFilePath()}'];

  // Filter out implementation-reserved identifiers that start with '_'.
  bool allowPublic(Declaration decl) => !decl.originalName.startsWith('_');

  for (final entry in Directory(opensslPublic.path).listSync(recursive: true)) {
    if (entry.path.endsWith('.h')) {
      headers.add(entry.uri);
    }
  }

  FfiGenerator(
    headers: Headers(entryPoints: headers, compilerOptions: compilerOpts),
    functions: Functions(include: allowPublic),
    macros: Macros(include: allowPublic),
    globals: Globals(include: allowPublic),
    enums: Enums(include: allowPublic),
    output: Output(dartFile: packageRoot.resolve('lib/src/third_party/openssl.g.dart')),
  ).generate(logger: logger);
}
