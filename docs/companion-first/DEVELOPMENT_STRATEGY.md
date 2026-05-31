# Here I am - Development Strategy

Status: Active

Effective date: 2026-06-01

## 1. One Product Mainline

`Here I am` is the only actively developed product line.

The upstream Memex project remains an important foundation and a read-only
reference. It is not a second product that must receive every local fix or new
feature.

From this date forward:

- New product work is implemented once in the `Here I am` codebase.
- Bug fixes are implemented once in the `Here I am` codebase.
- The legacy Memex app may remain installed temporarily for migration checks
  and behavioral comparisons.
- The upstream Memex repository remains configured as `upstream` so useful
  changes can still be reviewed selectively.

## 2. Upstream Relationship

`Here I am` is a GPL-3.0 derivative of
[memex-lab/memex](https://github.com/memex-lab/memex). It should preserve the
upstream license, clearly state that it is modified, and distinguish upstream
capabilities from personal contributions.

When a fix is broadly useful to Memex:

1. Implement and verify it in `Here I am`.
2. Keep the fix in a focused commit where practical.
3. Optionally submit that commit upstream as a pull request or cherry-pick it
   into an upstream maintenance branch.

Do not manually reimplement the same change in two working copies.

## 3. Repository Shape

Recommended remotes:

```text
origin      https://github.com/Ritou-Lynx/here-i-am.git
memex-fork  https://github.com/Ritou-Lynx/Memex.git
upstream    https://github.com/memex-lab/memex
```

The personal repository should keep the existing Git history. Preserving
history makes attribution clear and keeps future upstream comparison possible.

Before publishing the repository:

- Rename the repository and README around `Here I am`.
- Keep `LICENSE` and upstream attribution.
- Add a clear product statement and contribution boundary.
- Review tracked files and commit history for secrets or personal data.
- Add screenshots only after the companion-first interface is presentable.


## 4. Commit Discipline

Prefer small commits with an explicit intent:

```text
feat(hereiam): companion-first product behavior
fix(core): reusable Memex foundation fix
docs(hereiam): product and portfolio documentation
upstream-sync: selectively incorporate upstream changes
```

This keeps the portfolio readable and makes reusable fixes easy to submit
upstream without maintaining two products.

## 5. Portfolio Positioning

Describe the project honestly as a substantial product iteration built on the
open-source Memex foundation.

The portfolio focus is the work added on top:

- Reframing a diary app into a companion-first personal AI product.
- Designing shared life memory and character-private relationship memory.
- Making every character equally capable of orchestrating user-facing tasks.
- Moving multimodal capture into the conversation flow.
- Preserving local-first storage, migration, and inspectable review surfaces.
