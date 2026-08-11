---
date: '2026-08-11'
governs:
- .cz.toml
- recon/scripts/activate-plugin.sh
- recon/scripts/activate-codex-plugin.sh
- tools/render-system-map.py
- tools/test-system-map.sh
- tools/test-codex-activation.sh
id: SPEC-01KZRNHBT9MF1GZHSA205NS07X
references:
- ADR-01KZ0ZK4WYVWRY0WJM2CZ7ZS8C
status: implemented
---

# SPEC-01KZRNHBT9MF1GZHSA205NS07X Release And Activation Rails Fail Honestly

## Overview

Three rails reported success or advisory noise where they should have refused,
and the combination let a distribution mirror rot for two releases while
carrying unreleased work:

1. **The release refused itself.** `docs/system-map.html` stored a whole-file
   SHA-256 of `docs/flow.html`, which `cz bump` rewrites. The bump is a real
   commit, so its pre-commit hook ran `check-coherence.sh` before the map could
   be regenerated, and `render-system-map.py --check` failed with
   `generated system map drifted`. Fixed in v0.20.0; this SPEC records it and
   closes the class.
2. **Activation reported success over a stale mirror.** `activate-plugin.sh`
   printed `clone: … SYNC FAILED — …` and still exited 0, because the cache copy
   had already succeeded. A clone that cannot fast-forward is the signature of
   someone having edited a distribution mirror, and it was reported as a note.
3. **Codex activation died instead of reporting.** `codex plugin marketplace
   list --json` fails wholesale when any configured marketplace cannot load,
   writing nothing to stdout. Piping that into `json.load` surfaced a raw
   `JSONDecodeError` traceback instead of the cause codex names.

Separately, the prose that states the executable contract's version had gone
five releases stale (`0.15.0` in `recon/docs/hosts.md`, `recon/docs/pipeline.md`,
and `README.md`) because nothing rewrote it.

**Falsifiable claim:** a bump-stamped file's reference hash does not move when a
release renumbers its stamps, while any other content change to that file —
including a removed trailing newline — still drifts the map; the version prose is
rewritten by the bump and enforced by `check-coherence.sh`; a failed marketplace
clone sync exits non-zero; and an unreadable marketplace listing refuses with
codex's own words and no traceback.

This is bounded release/activation rail behavior. It changes no artifact schema,
gate semantic, evidence requirement, or routing rule.

## Technical Design

`.cz.toml`'s `version_files` is the sole owner of "which lines a bump rewrites".
`render-system-map.py` derives its normalization from that list
(`bump_stamped_markers`), so registering a new stamped file cannot reintroduce
problem 1 — previously the marker tokens were restated in the generator and its
test. `digest` normalizes `\d+\.\d+\.\d+` to `<version>` on only the lines
matching that file's registered markers, and hashes with `splitlines(keepends=True)`
so separator identity — a stripped trailing newline, a CRLF conversion — remains
drift.

The three stale sentences carry `coherence:version` and say `v<VERSION>`;
`check-coherence.sh` already fails any marked line that disagrees with
`plugin.json`. `recon/docs/pipeline.md` is also hashed reference R1, so it is
safe only because normalization is derived from the same list.

`activate-plugin.sh` retains the clone-sync failure and exits non-zero after
reporting it, naming the resolution: the source repo is the only editable
location. `activate-codex-plugin.sh` captures the listing command's combined
output and refuses with it, quoting codex verbatim.

## Testing Strategy

`tools/test-system-map.sh` simulates a real bump (renumbering marked lines) and
requires the map to stay clean, then requires drift for an unmarked version
change, appended content, and a removed trailing newline. A structural control
asserts every hashed ref that is bump-stamped is covered by the derivation.
`tools/test-codex-activation.sh` adds a listing-failure case to its fake-codex
harness. Both run under `check-coherence.sh`.

## Acceptance Criteria

- [x] Renumbering a bump-stamped line leaves the generated map `--check` clean.
- [x] An unmarked version change in a stamped file still drifts the map.
- [x] Appended content in a stamped file still drifts the map.
- [x] Removing a stamped file's trailing newline still drifts the map.
- [x] Every hashed reference that appears in `version_files` is normalized, proven
      structurally rather than by restating the marker list.
- [x] `recon/docs/hosts.md`, `recon/docs/pipeline.md`, and `README.md` state the
      current version and are rewritten by the bump.
- [x] `check-coherence.sh` fails when a marked line disagrees with `plugin.json`.
- [x] `activate-plugin.sh` exits non-zero when the marketplace clone cannot sync.
- [x] `activate-codex-plugin.sh` refuses with codex's own message, and no raw
      traceback, when the marketplace listing cannot be read.
