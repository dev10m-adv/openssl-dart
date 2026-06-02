import 'dart:io';

import 'libcrypto_headers.dart';

/// Removes single-line [external] libssl/TLS declarations and incomplete blocks.
///
/// After trimming, run `dart test` and `dart analyze`. Regenerate with
/// [tool/ffigen.dart] when upgrading OpenSSL.
void main() {
  final packageRoot = Platform.script.resolve('../');
  final bindingsFile = packageRoot.resolve('lib/src/third_party/openssl.g.dart');
  final input = File.fromUri(bindingsFile);
  if (!input.existsSync()) {
    stderr.writeln('Missing ${bindingsFile.toFilePath()}');
    exit(1);
  }

  final lines = input.readAsLinesSync();
  final out = <String>[];
  var removed = 0;
  var i = 0;

  while (i < lines.length) {
    if (lines[i].startsWith('@ffi.Native')) {
      final start = i;
      i++;
      while (i < lines.length && !_endsNativeBinding(lines, i)) {
        if (lines[i].startsWith('final class ')) break;
        if (i - start > 64) break;
        i++;
      }
      if (i < lines.length && _endsNativeBinding(lines, i)) {
        i++;
      }
      final block = lines.sublist(start, i);
      final hasExternal = block.any((l) => l.startsWith('external'));
      if (hasExternal && _shouldKeepBlock(block)) {
        out.addAll(block);
      } else {
        removed += block.length;
        while (i < lines.length &&
            !lines[i].startsWith('@ffi.Native') &&
            !lines[i].startsWith('final class ')) {
          removed++;
          i++;
        }
      }
      continue;
    }

    if (RegExp(r'^final class ssl').hasMatch(lines[i])) {
      removed++;
      i++;
      continue;
    }

    if (_isDanglingLine(lines[i])) {
      removed++;
      i++;
      continue;
    }

    out.add(lines[i]);
    i++;
  }

  input.writeAsStringSync('${out.join('\n')}\n');
  stdout.writeln('trim_bindings: removed $removed lines, kept ${out.length} lines');
}

bool _endsNativeBinding(List<String> lines, int index) =>
    lines[index].startsWith('external') && lines[index].trim().endsWith(';');

bool _shouldKeepBlock(List<String> block) {
  final text = block.join('\n');
  if (!includeBindingText(text)) return false;
  if (RegExp(r'\bssl\w*_st\b|<ssl\b|\bSSL_|\bDTLS_|\bOSSL_QUIC|\bossl_quic').hasMatch(text)) {
    return false;
  }
  for (final line in block) {
    if (line.startsWith('external')) {
      final name = RegExp(r'^external\s+[\w<>,\s\*\[\]]+\s+(\w+)').firstMatch(line)?.group(1);
      if (name != null && !includeDeclaration(name)) return false;
    }
  }
  return true;
}

bool _isDanglingLine(String line) =>
    line.contains('idtype_t') ||
    line.contains('TLS_ST_') ||
    RegExp(r'=> P_(ALL|PID|PGID)\b').hasMatch(line) ||
    line.contains('ssl_st') ||
    line.contains('SSL_get_state') ||
    line.contains('_SSL_get_state');
