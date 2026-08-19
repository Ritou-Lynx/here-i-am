const reasoningEfforts = new Set([
  'minimal',
  'low',
  'medium',
  'high',
  'xhigh',
  'max',
]);
const serviceTiers = new Set(['fast']);
const verbosities = new Set(['low', 'medium', 'high']);

function optionalString(value) {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

export function normalizeCodexOptions(raw, legacyModel = null) {
  const source = raw && typeof raw === 'object' ? raw : {};
  const options = {
    model: optionalString(source.model) || optionalString(legacyModel),
    reasoningEffort: optionalString(source.reasoning_effort)?.toLowerCase() || null,
    serviceTier: optionalString(source.service_tier)?.toLowerCase() || null,
    verbosity: optionalString(source.verbosity)?.toLowerCase() || null,
  };
  if (options.reasoningEffort && !reasoningEfforts.has(options.reasoningEffort)) {
    throw new Error(`unsupported Codex reasoning effort: ${options.reasoningEffort}`);
  }
  if (options.serviceTier && !serviceTiers.has(options.serviceTier)) {
    throw new Error(`unsupported Codex service tier: ${options.serviceTier}`);
  }
  if (options.verbosity && !verbosities.has(options.verbosity)) {
    throw new Error(`unsupported Codex verbosity: ${options.verbosity}`);
  }
  return options;
}

export function appendCodexOptionArgs(args, options, fallbackModel = null) {
  const model = options.model || optionalString(fallbackModel);
  if (model) args.push('-m', model);
  if (options.reasoningEffort) {
    args.push('-c', `model_reasoning_effort="${options.reasoningEffort}"`);
  }
  if (options.serviceTier) {
    args.push('-c', `service_tier="${options.serviceTier}"`);
  }
  if (options.verbosity) {
    args.push('-c', `model_verbosity="${options.verbosity}"`);
  }
  return args;
}
