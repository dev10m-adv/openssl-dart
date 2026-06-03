import 'dart:io';

/// Runs repository health checks (manifest, submodule, hash, prebuilts).
void main(List<String> args) async {
  final allowPartial = args.contains('--allow-partial');
  final verifyArgs = allowPartial ? ['--allow-partial'] : <String>[];

  final steps = <_Step>[
    _Step('sign_prebuilts', ['tool/sign_prebuilts.dart', '--check', ...verifyArgs]),
    _Step('check_submodule', ['tool/check_submodule.dart']),
    _Step('compute_build_hash', ['tool/compute_build_hash.dart']),
    _Step('verify_prebuilts', ['tool/verify_prebuilts.dart', ...verifyArgs]),
  ];

  for (final step in steps) {
    stdout.writeln('check_repo: ${step.name}');
    final result = await Process.run('dart', ['run', ...step.args]);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode != 0) {
      stderr.writeln('check_repo: failed at ${step.name}');
      exit(result.exitCode);
    }
  }

  stdout.writeln('check_repo: all checks passed');
}

class _Step {
  _Step(this.name, this.args);
  final String name;
  final List<String> args;
}
