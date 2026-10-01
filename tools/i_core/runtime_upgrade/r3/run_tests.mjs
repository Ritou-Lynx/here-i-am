import { assertNode } from './package.mjs';
import { runSyntheticTests } from './supervised_tests.mjs';

if (process.argv.slice(2).length !== 1 || process.argv[2] !== '--synthetic') {
  console.error('Explicit --synthetic is required; only self-created temporary fixtures are used.');
  process.exitCode = 2;
} else {
  assertNode();
  const cancellation = new AbortController();
  const cancel = () => cancellation.abort();
  process.once('SIGINT', cancel); process.once('SIGTERM', cancel);
  try {
    const result = await runSyntheticTests({ signal: cancellation.signal });
    process.stdout.write(result.output);
    console.log(JSON.stringify({ ...result, output: undefined }));
    process.exitCode = result.exit_code;
  } finally { process.off('SIGINT', cancel); process.off('SIGTERM', cancel); }
}
