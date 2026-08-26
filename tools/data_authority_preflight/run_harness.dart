import 'dart:io';

import 'lib/isolation_harness.dart';

void main(List<String> arguments) {
  final options = _parse(arguments);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tools/data_authority_preflight/run_harness.dart --fixture-root <dir> --output-root <temporary-dir>',
    );
    exitCode = 64;
    return;
  }
  try {
    final harness = IsolationHarness(
      repositoryRoot: Directory.current.path,
      fixtureBase:
          '${Directory.current.path}${Platform.pathSeparator}tools${Platform.pathSeparator}data_authority_preflight${Platform.pathSeparator}fixtures',
    );
    final result = harness.run(
      fixtureRoot: options['fixture-root']!,
      outputRoot: options['output-root']!,
    );
    stdout.writeln(
      'validate-only: ${result.reportBytes.length} deterministic bytes written',
    );
  } on HarnessFailure catch (failure) {
    stderr.writeln(failure);
    exitCode = 2;
  }
}

Map<String, String>? _parse(List<String> arguments) {
  if (arguments.length != 4) return null;
  final options = <String, String>{};
  for (var index = 0; index < arguments.length; index += 2) {
    final key = arguments[index];
    if ((key != '--fixture-root' && key != '--output-root') ||
        options.containsKey(key.substring(2))) {
      return null;
    }
    options[key.substring(2)] = arguments[index + 1];
  }
  return options.length == 2 ? options : null;
}
