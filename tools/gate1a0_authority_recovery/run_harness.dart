import 'dart:io';

import 'lib/synthetic_harness.dart';

void main(List<String> arguments) {
  if (arguments.length != 4 ||
      arguments[0] != '--fixture-root' ||
      arguments[2] != '--output-root') {
    stderr.writeln(
      'Usage: dart run tools/gate1a0_authority_recovery/run_harness.dart --fixture-root <fixture-dir> --output-root <empty-system-temp-dir>',
    );
    exitCode = 64;
    return;
  }
  try {
    final result = SyntheticAuthorityRecoveryHarness(
      repositoryRoot: Directory.current.path,
      fixtureBase:
          '${Directory.current.path}${Platform.pathSeparator}tools${Platform.pathSeparator}gate1a0_authority_recovery${Platform.pathSeparator}fixtures',
    ).run(fixtureRoot: arguments[1], outputRoot: arguments[3]);
    stdout.writeln(
      'validate/simulate-only: ${result.reportBytes.length} deterministic bytes written',
    );
  } on HarnessFailure catch (error) {
    stderr.writeln(error);
    exitCode = 2;
  }
}
