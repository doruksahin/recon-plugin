# Attest Codex activation to the released bytes

> Never report a source version when Codex actually reinstalled an older clone

- **Status:** shipped (v0.15.0)
- **Priority:** P1
- **Theme:** release integrity
- **Origin:** The 2 Aug 2026 delivery-risk agent found the configured Codex
  marketplace at `/Users/doruk/Desktop/ADCREATIVE/recon-plugin`, while release
  work ran from `/Users/doruk/Documents/recon-plugin`. A live audit confirmed
  the configured clone was behind and Codex loaded v0.14.1 from it.

## Problem

In v0.14.1, `activate-codex-plugin.sh` read the desired version from the source
checkout, but `codex plugin add` read bytes from the separately configured
marketplace. For a local marketplace, `codex plugin marketplace upgrade` did not
update that clone; the script ignored the failure and printed the source version
anyway.

This created the worst release outcome: a green activation line with old skills.

## Before (v0.14.1)

```text
source:      /Documents/recon-plugin → v0.15.0
configured:  /Desktop/ADCREATIVE/recon-plugin → v0.14.1
upgrade:     was ignored because the marketplace was local
plugin add:  installed the configured v0.14.1 bytes
reported:    codex: activated recon@recon-plugin v0.15.0
```

The report described intent, not installed state.

## After (implemented)

```text
codex: marketplace clone synced — /Desktop/ADCREATIVE/recon-plugin
codex: activated recon@recon-plugin v0.15.0
codex: verified v0.15.0 commit <released-sha> tree sha256:<digest> entries:<n> from /Desktop/ADCREATIVE/recon-plugin/recon

$ bash tools/test-codex-activation.sh
codex activation contract: PASS
```

Success requires clean same-origin source and configured checkouts, a fast-forward
update, and exact Git HEAD, manifest, and materialized plugin-tree equality before
installation, after `codex plugin add`, and once more immediately after Codex's
installation JSON is read. The tree attestation binds each
relative path, regular-file bytes, symlink target, and executable bit; ignored,
excluded, untracked, sparse, assume-unchanged, or special filesystem entries are
rejected. Codex's JSON must then report the exact enabled version and attested
source path. Any mismatch fails without claiming activation.

## Implementation sketch

- Read the configured marketplace root and source type from Codex JSON.
- For a separate local git checkout, require clean state and matching normalized
  origin, then `git pull --ff-only` after the release has pushed.
- Require both checkouts to remain clean and match the released source commit;
  reject sparse/assume-unchanged index state and materialized plugin content that
  is untracked, ignored, excluded, missing, or a special file.
- Hash deterministic materialized-tree records (relative path, type, executable
  bit, regular-file bytes or symlink target) and require source/configured equality.
- Reinstall through the public Codex CLI.
- Re-attest HEAD, version, path, cleanliness, and both materialized trees after
  installation and again after the installation-list query, closing mutation
  windows in both external Codex calls before success is printed.
- Query `codex plugin list --json`; attest ID, enabled state, exact version, and
  a source path under the configured marketplace root.
- Add fake-Codex fixtures for successful sync plus stale-install, dirty-source,
  dirty-clone, post-sync-dirty, same-version/different-content, ignored rogue
  skill, sparse omission, assume-unchanged, post-add mutation, and list-time
  ignored mutation refusals.

Implemented under
*SPEC-01KZ14Q6A2WB6J6TTX3XWQC5QJ Recon 0.15.0 Verified Handoff Chain*.

## Open questions

- A deliberately non-git local marketplace cannot be synchronized safely. Fail
  with an exact reconfiguration command rather than copying over it.
- The current `recon/` tree has no symlinks. Attestation hashes a tracked
  symlink's target string, but does not dereference it; before introducing one,
  either forbid plugin symlinks or require every target to resolve inside the
  tracked plugin tree.
