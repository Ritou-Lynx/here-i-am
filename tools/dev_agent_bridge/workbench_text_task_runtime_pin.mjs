// R7 candidate observed 2026-09-11. Same version string, different executable.
// This pin permits candidate testing; it is never an isolation receipt.
import { createHash } from 'node:crypto';
import { lstatSync, readFileSync, realpathSync } from 'node:fs';
import path from 'node:path';

export const TEXT_TASK_CLI_SHA256 = '3d6ca7085c932b62ef4ee4877e92f15b050fb94b2eb8e6c10a346a06248c6004';

export function assertTextTaskExecutable(executable) {
  if (typeof executable !== 'string' || !path.isAbsolute(executable)
    || path.basename(executable).toLowerCase() !== 'codex.exe') throw new Error('text_task_runtime_pin_mismatch');
  for (let current = executable; current !== path.dirname(current); current = path.dirname(current)) {
    if (lstatSync(current).isSymbolicLink() || path.relative(current, realpathSync(current)) !== '') {
      throw new Error('text_task_runtime_path_redirected');
    }
  }
  if (!lstatSync(executable).isFile()
    || createHash('sha256').update(readFileSync(executable)).digest('hex') !== TEXT_TASK_CLI_SHA256) {
    throw new Error('text_task_runtime_pin_mismatch');
  }
  return realpathSync(executable);
}
