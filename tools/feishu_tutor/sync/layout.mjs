import { realpath } from 'node:fs/promises';
import path from 'node:path';
import { fail } from './cli.mjs';

// Resolve existing ancestors too: state/ may not exist yet, and junctions or
// symlinks must not turn a seemingly separate directory into writable tools.
export async function resolvedPath(value) {
  const absolute = path.resolve(value);
  try { return await realpath(absolute); }
  catch (error) {
    if (error.code !== 'ENOENT' || path.dirname(absolute) === absolute) throw error;
    return path.join(await resolvedPath(path.dirname(absolute)), path.basename(absolute));
  }
}

function contains(parent, child) {
  const relative = path.relative(parent, child);
  return relative === '' || (!path.isAbsolute(relative) && relative !== '..' && !relative.startsWith(`..${path.sep}`));
}

export async function assertSeparateDirectories(studyDirectory, toolDirectories) {
  const requestedStudy = path.resolve(studyDirectory);
  const study = await resolvedPath(studyDirectory);
  for (const directory of toolDirectories) {
    const requestedTool = path.resolve(directory);
    const tool = await resolvedPath(directory);
    if (contains(requestedStudy, requestedTool) || contains(requestedTool, requestedStudy) ||
        contains(study, tool) || contains(tool, study)) fail('daily_layout_invalid');
  }
}
