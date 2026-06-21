# Dev Agent MyPilot Probe

Date: 2026-06-21

## Result

MyPilot is not usable on the current Windows development machine yet.

The previous global command was only a stale npm shim. Reinstalling
`mypilot@0.5.0` fails during native `node-pty` setup.

## Findings

- `mypilot@0.5.0` ships a `postinstall` script:
  `cd node_modules/node-pty && npx node-gyp rebuild`.
- That path is brittle under the current npm layout and fails during install.
- Installing `node-pty@1.0.0` directly also fails on this machine because
  Visual Studio Build Tools is missing Spectre-mitigated libraries for the
  active C++ toolset.
- Node/npm environment at probe time:
  - Node: `v24.14.1`
  - npm: `11.11.0`

## Decision

Continue Phase 1/2 app and protocol work on the project-local bridge while
leaving MyPilot as the preferred long-term base for hook interception, reconnect
semantics, and remote-control UX.

Before returning to the MyPilot fork path, install the missing Visual Studio C++
Spectre libraries or use a Node version / package layout with a prebuilt
`node-pty` binary.
