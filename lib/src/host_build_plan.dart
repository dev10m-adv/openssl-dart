import 'dart:io';

import 'package:code_assets/code_assets.dart';

import 'build_target.dart';
import 'prebuilt_paths.dart';

/// One row in the native prebuilt build plan for the current host.
class NativeBuildPlanEntry {
  const NativeBuildPlanEntry({
    required this.triple,
    required this.buildable,
    this.skipReason,
  });

  final String triple;
  final bool buildable;
  final String? skipReason;
}

/// Maps a prebuilt folder name to the code-asset target OS.
OS? tripleTargetOS(String triple) {
  if (triple.startsWith('windows-')) return OS.windows;
  if (triple.startsWith('linux-')) return OS.linux;
  if (triple.startsWith('android-')) return OS.android;
  if (triple == 'macos-universal') return OS.macOS;
  if (triple == 'ios-xcframework') return OS.iOS;
  return null;
}

/// All known prebuilt triples (required + optional).
List<String> allPrebuiltTriples() => [
      ...requiredPrebuiltTriples,
      ...optionalPrebuiltTriples.where((t) => !requiredPrebuiltTriples.contains(t)),
    ];

/// Whether [triple] can be compiled on this machine with bundled scripts.
NativeBuildPlanEntry planTriple(String triple) {
  final targetOS = tripleTargetOS(triple);
  if (targetOS == null) {
    return NativeBuildPlanEntry(
      triple: triple,
      buildable: false,
      skipReason: 'Unknown prebuilt triple',
    );
  }

  final hostOS = OS.current;
  if (hostOS == OS.windows) {
    if (triple == 'windows-x64' || triple == 'windows-arm64') {
      return NativeBuildPlanEntry(triple: triple, buildable: true);
    }
  }

  if (hostOS == OS.linux) {
    if (triple.startsWith('linux-')) {
      return NativeBuildPlanEntry(triple: triple, buildable: true);
    }
    if (triple.startsWith('android-') && _hasAndroidNdk()) {
      return NativeBuildPlanEntry(triple: triple, buildable: true);
    }
    if (triple.startsWith('android-')) {
      return NativeBuildPlanEntry(
        triple: triple,
        buildable: false,
        skipReason: 'Set ANDROID_NDK_ROOT or install Android NDK',
      );
    }
  }

  if (hostOS == OS.macOS) {
    if (triple == 'macos-universal' || triple == 'ios-xcframework') {
      return NativeBuildPlanEntry(triple: triple, buildable: true);
    }
    if (triple.startsWith('linux-')) {
      return NativeBuildPlanEntry(triple: triple, buildable: true);
    }
    if (triple.startsWith('android-') && _hasAndroidNdk()) {
      return NativeBuildPlanEntry(triple: triple, buildable: true);
    }
    if (triple.startsWith('android-')) {
      return NativeBuildPlanEntry(
        triple: triple,
        buildable: false,
        skipReason: 'Set ANDROID_NDK_ROOT or install Android NDK',
      );
    }
  }

  final requirement = compileHostRequirement(hostOS, targetOS);
  return NativeBuildPlanEntry(
    triple: triple,
    buildable: false,
    skipReason: requirement ?? 'Not buildable on ${hostOS.name} host',
  );
}

/// Build plan for every known triple on the current host.
List<NativeBuildPlanEntry> planAllNativeBuilds() {
  return allPrebuiltTriples().map(planTriple).toList();
}

/// Triples this host can attempt to build locally.
List<String> buildableTriplesOnHost() {
  return planAllNativeBuilds()
      .where((e) => e.buildable)
      .map((e) => e.triple)
      .toList();
}

String defaultHostTriple() {
  if (Platform.isWindows) {
    final arch = (Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '').toUpperCase();
    return arch.contains('ARM64') ? 'windows-arm64' : 'windows-x64';
  }
  if (Platform.isLinux) {
    final machine = Platform.environment['PROCESSOR_ARCHITECTURE'] ??
        _unameMachine() ??
        'x86_64';
    final lower = machine.toLowerCase();
    return lower.contains('aarch64') || lower.contains('arm64') ? 'linux-arm64' : 'linux-x64';
  }
  if (Platform.isMacOS) {
    return 'macos-universal';
  }
  throw UnsupportedError('Unsupported host OS: ${Platform.operatingSystem}');
}

bool _hasAndroidNdk() {
  for (final key in ['ANDROID_NDK_ROOT', 'ANDROID_NDK_HOME']) {
    final value = Platform.environment[key];
    if (value != null && value.isNotEmpty && Directory(value).existsSync()) {
      return true;
    }
  }
  const defaults = [
    r'C:\Android\android-ndk-r27c',
    r'C:\Android\Sdk\ndk\27.0.12077973',
  ];
  for (final path in defaults) {
    if (Directory(path).existsSync()) return true;
  }
  return false;
}

String? _unameMachine() {
  try {
    final result = Process.runSync('uname', ['-m']);
    if (result.exitCode == 0) return (result.stdout as String).trim();
  } on Object {
    // ignore
  }
  return null;
}
