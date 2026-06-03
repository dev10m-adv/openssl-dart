import 'dart:convert';
import 'dart:io';

const openSslPackageName = 'openssl';

/// Resolves the `openssl` package root from the app's package config, [explicitPath], or cwd.
Future<Directory> locateOpenSslPackageRoot({String? explicitPath}) async {
  if (explicitPath != null && explicitPath.isNotEmpty) {
    final dir = Directory(explicitPath);
    if (!_isOpenSslPackageRoot(dir)) {
      throw StateError('Not an openssl package root: ${dir.path}');
    }
    return dir;
  }

  if (_isOpenSslPackageRoot(Directory.current)) {
    return Directory.current;
  }

  final fromConfig = _tryLocateFromPackageConfig(Directory.current);
  if (fromConfig != null) {
    return fromConfig;
  }

  final pubCache = Platform.environment['PUB_CACHE'] ??
      (Platform.isWindows
          ? '${Platform.environment['LOCALAPPDATA']}\\Pub\\Cache'
          : '${Platform.environment['HOME']}/.pub-cache');

  final gitCache = Directory('$pubCache/git');
  if (!gitCache.existsSync()) {
    throw StateError(
      'Could not find openssl package.\n'
      'Run `flutter pub get` / `dart pub get` in your app first, or pass --path=.',
    );
  }

  final matches = <Directory>[];
  for (final entity in gitCache.listSync()) {
    if (entity is! Directory) continue;
    final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (!name.startsWith('$openSslPackageName-')) continue;
    if (_isOpenSslPackageRoot(entity)) {
      matches.add(entity);
    }
  }

  if (matches.isEmpty) {
    throw StateError(
      'Could not find openssl in pub cache.\n'
      'Add openssl to pubspec.yaml and run pub get, or pass --path=.',
    );
  }

  matches.sort((a, b) => b.path.compareTo(a.path));
  return matches.first;
}

Directory? _tryLocateFromPackageConfig(Directory start) {
  var dir = start;
  while (true) {
    final configFile = File('${dir.path}/.dart_tool/package_config.json');
    if (configFile.existsSync()) {
      try {
        final json = jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
        final packages = json['packages'] as List<dynamic>? ?? [];
        final configDir = Directory('${dir.path}${Platform.pathSeparator}.dart_tool');
        for (final pkg in packages) {
          if (pkg is! Map<String, dynamic>) continue;
          if (pkg['name'] != openSslPackageName) continue;
          final rootUri = pkg['rootUri'] as String?;
          if (rootUri == null) continue;
          final resolved = _resolvePackageRootUri(configDir.uri, rootUri);
          final packageDir = Directory.fromUri(resolved);
          if (_isOpenSslPackageRoot(packageDir)) {
            return packageDir;
          }
        }
      } on Object {
        return null;
      }
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      return null;
    }
    dir = parent;
  }
}

Uri _resolvePackageRootUri(Uri appRoot, String rootUri) {
  if (rootUri.startsWith('file:')) {
    return Uri.parse(rootUri);
  }
  return appRoot.resolve(rootUri);
}

bool _isOpenSslPackageRoot(Directory dir) {
  final pubspec = File('${dir.path}/pubspec.yaml');
  if (!pubspec.existsSync()) return false;
  return RegExp(r'^name:\s*openssl\s*$', multiLine: true)
      .hasMatch(pubspec.readAsStringSync());
}
