import assert from 'node:assert/strict';
import test from 'node:test';

import {
  appendCodexOptionArgs,
  normalizeCodexOptions,
} from './codex_run_options.mjs';

test('normalizes structured Codex controls and preserves legacy model', () => {
  assert.deepEqual(
    normalizeCodexOptions({
      reasoning_effort: 'HIGH',
      service_tier: 'fast',
      verbosity: 'low',
    }, 'gpt-legacy'),
    {
      model: 'gpt-legacy',
      reasoningEffort: 'high',
      serviceTier: 'fast',
      verbosity: 'low',
    },
  );
});

test('builds Codex CLI overrides independently', () => {
  const args = appendCodexOptionArgs([], {
    model: 'gpt-5.6-terra',
    reasoningEffort: 'medium',
    serviceTier: 'fast',
    verbosity: 'high',
  });
  assert.deepEqual(args, [
    '-m', 'gpt-5.6-terra',
    '-c', 'model_reasoning_effort="medium"',
    '-c', 'service_tier="fast"',
    '-c', 'model_verbosity="high"',
  ]);
});

test('rejects unsupported values before spawning Codex', () => {
  assert.throws(
    () => normalizeCodexOptions({ reasoning_effort: 'unlimited' }),
    /unsupported Codex reasoning effort/,
  );
});
