// Codex may serialize tools in input.additional_tools instead of top-level tools.
// Do not infer an empty catalog from a missing top-level field.
export function inspectCompiledToolCatalog(body) {
  if (!body || typeof body !== 'object' || !Array.isArray(body.input) || typeof body.model !== 'string') {
    throw new Error('Cannot inspect an unrecognized model request.');
  }
  const catalogs = [];
  const codeModeDeclarations = [];
  function visit(value, location) {
    if (!value || typeof value !== 'object') return;
    if (Array.isArray(value)) {
      value.forEach((item, index) => visit(item, `${location}[${index}]`));
      return;
    }
    for (const [key, child] of Object.entries(value)) {
      if (key === 'description' && typeof child === 'string') {
        const names = [...child.matchAll(/declare const tools:\s*\{\s*([A-Za-z0-9_]+)\s*\(/g)].map(match => match[1]);
        if (names.length) codeModeDeclarations.push({ location: `${location}.description`, names });
      }
      if (key === 'tools') {
        if (!Array.isArray(child)) throw new Error(`Unrecognized tool catalog at ${location}.tools`);
        catalogs.push({ location: `${location}.tools`, count: child.length,
          names: child.map(tool => String(tool?.name || tool?.type || 'unknown')) });
      }
      visit(child, `${location}.${key}`);
    }
  }
  visit(body, '$');
  return { catalogs, code_mode_declarations: codeModeDeclarations,
    no_tools: catalogs.every(catalog => catalog.count === 0) && codeModeDeclarations.length === 0 };
}

export function hasCompiledTool(inspection, name) {
  return inspection.catalogs?.some(catalog => catalog.names.includes(name)) === true
    || inspection.code_mode_declarations?.some(declaration => declaration.names.includes(name)) === true;
}
