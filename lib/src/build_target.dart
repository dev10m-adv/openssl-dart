import 'package:code_assets/code_assets.dart';

export 'native_version.dart' show openSslVersion, readOpenSslVersion;

/// OpenSSL Configure target for the given code asset target.
String resolveConfigName(OS os, Architecture architecture, IOSSdk? iosSdk) {
  final isIosSimulator = iosSdk == IOSSdk.iPhoneSimulator;
  return switch ((os, architecture)) {
    (OS.android, Architecture.arm) => 'android-arm',
    (OS.android, Architecture.arm64) => 'android-arm64',
    (OS.android, Architecture.ia32) => 'android-x86',
    (OS.android, Architecture.x64) => 'android-x86_64',
    (OS.android, Architecture.riscv64) => 'android-riscv64',
    (OS.iOS, Architecture.arm) => 'ios-xcrun',
    (OS.iOS, Architecture.arm64) => isIosSimulator ? 'iossimulator-arm64-xcrun' : 'ios64-xcrun',
    (OS.iOS, Architecture.ia32) => 'iossimulator-i386-xcrun',
    (OS.iOS, Architecture.x64) => 'iossimulator-x86_64-xcrun',
    (OS.macOS, Architecture.arm64) => 'darwin64-arm64',
    (OS.macOS, Architecture.x64) => 'darwin64-x86_64',
    (OS.macOS, Architecture.ia32) => 'darwin-i386',
    (OS.linux, Architecture.arm) => 'linux-armv4',
    (OS.linux, Architecture.arm64) => 'linux-aarch64',
    (OS.linux, Architecture.ia32) => 'linux-x86',
    (OS.linux, Architecture.x64) => 'linux-x86_64',
    (OS.linux, Architecture.riscv32) => 'linux32-riscv32',
    (OS.linux, Architecture.riscv64) => 'linux64-riscv64',
    (OS.windows, Architecture.arm) => 'VC-WIN32-ARM',
    (OS.windows, Architecture.arm64) => 'VC-WIN64-ARM',
    (OS.windows, Architecture.ia32) => 'VC-WIN32',
    (OS.windows, Architecture.x64) => 'VC-WIN64A',
    _ => throw UnsupportedError('Unsupported target combination: ${os.name}-${architecture.name}'),
  };
}

/// Artifact file name produced by OpenSSL build for this target.
String resolveLibFileName(OS os, Architecture architecture, LinkModePreference linkMode) {
  final preferStatic = linkMode == LinkModePreference.static || linkMode == LinkModePreference.preferStatic;
  return switch ((os, preferStatic)) {
    (OS.windows, true) => 'libcrypto_static.lib',
    (OS.windows, false) => 'libcrypto-3-${architecture.name}.dll',
    (OS.macOS || OS.iOS, true) => 'libcrypto.a',
    (OS.macOS || OS.iOS, false) => 'libcrypto.dylib',
    (OS.linux || OS.android, true) => 'libcrypto.a',
    (OS.linux || OS.android, false) => 'libcrypto.so',
    _ => throw UnsupportedError('Unsupported target OS: ${os.name}'),
  };
}

bool usesUnixMakefileBuild(OS targetOS) =>
    targetOS == OS.android || targetOS == OS.iOS || targetOS == OS.linux || targetOS == OS.macOS;

bool usesMsvcBuild(OS targetOS) => targetOS == OS.windows;

/// Whether [hostOS] can compile [targetOS] from source with the bundled hook.
bool canCompileOnHost(OS hostOS, OS targetOS) {
  if (hostOS == targetOS) return true;
  if (targetOS == OS.linux && (hostOS == OS.macOS || hostOS == OS.linux)) return true;
  return false;
}

String? compileHostRequirement(OS hostOS, OS targetOS) {
  if (canCompileOnHost(hostOS, targetOS)) return null;
  if (targetOS == OS.android || targetOS == OS.iOS) {
    return 'Building OpenSSL for ${targetOS.name} requires a macOS or Linux host, '
        'or use a prebuilt library under native/prebuilt/.';
  }
  if (targetOS == OS.linux && hostOS == OS.windows) {
    return 'Building OpenSSL for Linux on a Windows host is not supported. '
        'Use a prebuilt library under native/prebuilt/.';
  }
  if (targetOS == OS.macOS && hostOS != OS.macOS) {
    return 'Building OpenSSL for macOS requires a macOS host, or use a prebuilt library.';
  }
  if (targetOS == OS.windows && hostOS != OS.windows) {
    return 'Building OpenSSL for Windows requires a Windows host with MSVC, or use a prebuilt library.';
  }
  return 'Cannot compile OpenSSL for ${targetOS.name} on ${hostOS.name} host.';
}

List<String> configureArgsFor(OS targetOS) {
  const common = ['no-unit-test', 'no-makedepend', 'no-ssl', 'no-apps'];
  if (usesMsvcBuild(targetOS)) {
    return [...common, 'no-asm'];
  }
  return [...common, '-Wl,-headerpad_max_install_names'];
}
