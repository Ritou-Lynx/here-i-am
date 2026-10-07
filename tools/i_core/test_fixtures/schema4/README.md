# Public synthetic schema-v4 test input

This directory replaces an unavailable private-history fixture dependency. It does **not** restore `bbb8025d`, attest its source bytes, or authorize any deployment.

- `synthetic_schema4.mjs` freezes the eight legacy table definitions still present in the public `ICoreStore` and seeds one synthetic row per table, with valid references and identity. The unchanged production v4 guard checks the independent fixed column-shape digest. `Schema4Reader` checks chat/cursor preservation after migration rollback; opening existing owned state permits SQLite hot-journal recovery and never represents execution of the missing old constructor.
- `runtime_pin_lab.mjs` creates an owned temporary Git repository. The public server, relay, PowerShell sources, and activity dependency are copied byte-for-byte. Only the store's activity constructor is replaced by a dormant synthetic adapter so the package keeps schema 4. The rest of its core implementation and the complete server routing/authentication remain real public code.
- Only temporary builder/launcher copies receive the resulting real synthetic commit and the additional dependency inventory. Their release is explicitly `synthetic-public-schema4-test-only`. The production builder and launcher still require their original `bbb8025d` baseline and verified Node hash; tests also prove they reject absent historical blobs and synthetic provenance.
- Tests exercise the actual v4 guard, package hashes, source blob IDs, tamper rejection, wrapper environment clearing, Windows lock, HTTP authorization, and relay configuration boundary. They establish these contracts with synthetic input, **not** compatibility or acceptance of the unavailable historical executable.

All data and commits are created under each test's temporary root. No fixture uses private repository history, real state, credentials, or external services. Runtime pin tests keep their existing Windows-only boundary.
