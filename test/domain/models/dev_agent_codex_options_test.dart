import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/dev_agent_codex_options.dart';

void main() {
  test('run values override session values and inherit missing fields', () {
    const session = DevAgentCodexOptions(
      model: 'gpt-5.6-terra',
      reasoningEffort: 'medium',
      verbosity: 'medium',
    );
    const run = DevAgentCodexOptions(
      reasoningEffort: 'high',
      serviceTier: 'fast',
    );

    expect(
      run.withFallback(session).toJson(),
      {
        'model': 'gpt-5.6-terra',
        'reasoning_effort': 'high',
        'service_tier': 'fast',
        'verbosity': 'medium',
      },
    );
  });

  test('quick preset changes depth and detail without enabling Fast tier', () {
    expect(DevAgentCodexOptions.quick.reasoningEffort, 'low');
    expect(DevAgentCodexOptions.quick.verbosity, 'low');
    expect(DevAgentCodexOptions.quick.serviceTier, isNull);
  });
}
