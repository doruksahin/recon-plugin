---
date: '2026-09-05'
governs:
- recon/scripts/store-dossier.sh
- recon/scripts/CLAUDE.md
- recon/skills/CLAUDE.md
- recon/skills/recon-report/SKILL.md
- recon/docs/storage.md
- recon/docs/CLAUDE.md
- recon/docs/pipeline.md
- recon/docs/hosts.md
- README.md
- docs/flow.html
- docs/system-map.html
- tools/test-dossier-store.sh
- tools/check-coherence.sh
- tools/CLAUDE.md
id: SPEC-01M1SMA0CR7BCGE0821Z46YWYW
references:
- ADR-01KZ0ZK4WYVWRY0WJM2CZ7ZS8C
status: implemented
---

# SPEC-01M1SMA0CR7BCGE0821Z46YWYW Recon Task Packet Store Delivery

## Overview

Recon can render a complete current-run dossier, but its only delivery paths
are a host-native private artifact or a human-approved Jira attachment. The
reusable-storage delivery dated 2026-09-05 requires Recon to become a second
consumer of the existing `@doruksahin/task-packet-store` contract without
making storage select a host, authorize Jira, or introduce another transport.

This SPEC adds one explicit delivery-only command. It accepts an absolute
credential-free store configuration, a ticket, and the current ticket
workspace containing an already rendered dossier. The command stores all
registered current-run support files under `stages/10-recon/runs/vN/`, omits
the unreadable top-level `runs/` archive, and reports the actual stored run and
`report/dossier.html` locations. Existing report behavior is unchanged unless
the operator explicitly supplies a store.

The bounded claim is that one already-rendered Recon current run can be saved
through the published filesystem or Google Drive transport with a truthful
success receipt. This does not claim new dossier judgment, storage durability
for a temporary filesystem root, Jira delivery, host publication, or quality
across untested stores.

## Technical Design

`recon/scripts/store-dossier.sh` is the only new execution path. Its literal
interface is:

```bash
bash recon/scripts/store-dossier.sh \
  --store /absolute/path/store.json \
  --ticket PROJ-123 \
  --source /absolute/path/to/recon-root/PROJ-123
```

The source is the current ticket workspace, not its `report/` directory. The
rail requires regular `meta.yaml`, `triage/triage.yaml`, and
`report/dossier.html` files and requires the source basename and metadata
ticket to equal `--ticket`. It copies the current-run tree to temporary local
staging while pruning top-level `runs/` before traversal and rejecting
symlinks or non-regular entries. The traversal completes into a checked entry
list before copying begins; a traversal error therefore cannot silently omit
current-run evidence. It runs `lint-workspace.sh` against that staged tree, so
storage sees the same artifact registry without reading an archive or writing
a receipt/state artifact into the live Recon workspace.

The rail invokes exactly
`@doruksahin/task-packet-store@0.1.1` through npm's one-off CLI path. It sets
the package's public scoped registry for that subprocess while preserving the
rest of the operator environment. The package remains the sole owner of store
JSON validation, filesystem and Drive transports, credentials, run numbering,
checkpoint inventory, and location lookup. `begin` reserves stage
`10-recon`; `--tool` is `recon@<plugin_version from meta.yaml>`. One final
`checkpoint` uploads the complete staged current run. Four `locate` calls
resolve the reserved run directory, `report/dossier.html`, `run.md`, and
`snapshot.json`.

Before traversal or `begin`, the rail calls the package's read-only `doctor`
command. That command remains the owner of config validation and returns the
selected driver plus its `remoteRoot`. For filesystem stores, the rail resolves
the prospective `<remoteRoot>/<ticket>` destination through existing symlink
ancestors and rejects equality or either ancestor relationship with the
canonical source. Drive roots are not interpreted as local paths.

The rail captures every package JSON response internally. It writes exactly
one JSON object to stdout only after `begin`, `checkpoint`, and both `locate`
calls return coherent results. The receipt names the pinned package, Recon
tool provenance, ticket, stage, store version, checkpoint inventory, source,
primary result, and the two package-owned location objects. Any validation,
package, checkpoint, or lookup failure exits nonzero with a phase-specific
diagnostic and no success object. A failure after `begin` may leave the
package-owned reserved run record, but it cannot be reported as persisted.

`recon-report` invokes this rail only when an absolute store path was
explicitly supplied for that report run. No store means the current render or
host-publication behavior. Storage is independent of the existing
`publish_once` capability and never grants Jira approval; render-only Jira
paths do not store unless their caller explicitly supplied the store input.

## Testing Strategy

`tools/test-dossier-store.sh` uses a fake `npm` executable to exercise the
adapter orchestration without network, Drive credentials, or a second
transport implementation. It verifies the exact package/version invocation,
the fixed stage/tool inputs, package response coherence, current-run support
file staging, archive pruning, and the final receipt. It repeats a successful
delivery and requires the second version while proving the first is unchanged.
Fault fixtures cover invalid inputs, incomplete current-run traversal,
filesystem source/destination overlap (direct, descendant, and symlink alias),
workspace lint failure, checkpoint failure, and location failure; each must
exit nonzero and keep stdout empty. Traversal and overlap failures must occur
before `begin`, leave no reservation, and preserve the source bytes; an
unreadable top-level archive remains a passing negative control.

A local acceptance run uses the real published package and an `fs` config. It
saves a rendered fixture with support files, reads the returned filesystem
locations, compares saved bytes and snapshot inventory, repeats the delivery,
and proves `v1` remains unchanged. This run must not have rclone or Drive
credentials in its isolated environment.

The Drive acceptance recipe uses the same Recon command, an existing valid
`gdrive` config, environment-only packet-store credentials, and an isolated
prefix. It checks the returned run-folder and dossier URLs, then repeats and
checks that the prior run location and bytes remain available. No Drive write
is part of repository validation; private CI owns that acceptance.

## Acceptance Criteria

- [x] The documented command accepts absolute `--store`, `--ticket`, and
      current-workspace `--source` inputs and pins
      `@doruksahin/task-packet-store@0.1.1`.
- [x] The adapter reserves `stages/10-recon/runs/vN`, checkpoints the complete
      registered current run, includes supporting evidence, and never reads or
      stores top-level `runs/`.
- [x] A success receipt is emitted only after the checkpoint plus run and
      `report/dossier.html` location lookups succeed.
- [x] No-store report behavior, host publication, Jira delivery gates, and
      governance routing retain their existing semantics.
- [x] Hermetic adapter controls pass for exact invocation, repeat delivery,
      checked current-run traversal, archive exclusion, filesystem overlap,
      invalid input, checkpoint failure, and lookup failure.
- [x] A real `fs` run works without rclone or Drive credentials, returned
      locations are readable, and repeating it preserves `v1`.
- [x] The deterministic Drive acceptance recipe uses the identical adapter
      with environment credentials and no plugin-owned transport.
- [x] Generated adapters, link/coherence checks, and the complete pre-commit
      rail pass.

## Completed Outcome

On 2026-09-05, the hermetic adapter suite passed eight contract groups,
including support-file inclusion, archive pruning, repeat preservation, and
empty-stdout checkpoint/location failures. A separate run through the real
published `@doruksahin/task-packet-store@0.1.0` filesystem transport reserved
`v1` and `v2`, returned readable locations for the run, dossier, run record,
and snapshot, read back the support file, omitted archived `runs/`, and left
the `v1` dossier SHA-256 unchanged after `v2`. The full pre-commit rail passed.

Live Google Drive mutation remains private acceptance, not a repository-side
claim. `recon/docs/storage.md` fixes the identical-adapter recipe and explicit
credential/location checks for that run.

On 2026-09-06, independent review reproduced two fail-open boundaries in the
initial implementation: a failed `find` hidden by process substitution could
omit unreadable support evidence, and an overlapping filesystem destination
could let `begin` write into the source. The revised eleven-group hermetic suite
retains both failures and their negative controls. Checked traversal now stops
before staging or reservation, and package-owned `doctor` metadata drives a
canonical overlap guard before `begin`, including symlink aliases and a
not-yet-created destination below the source. The revised rail was then run
twice through the real published filesystem transport: `v1` and `v2` resolved
all four locations, retained the supporting session bytes, omitted the
unreadable archive, and a real overlap attempt exited nonzero with empty stdout
before creating `stages/` in the source.

Later on 2026-09-06, a live filesystem execution outside Recon exposed an
upstream `0.1.0` transport defect: a checkpoint could not replace a destination
file sealed read-only by the prior checkpoint. Recon's begin-per-delivery
`vN` behavior remained valid, but its current pin moved to the corrected
`0.1.1` package so consumers select the repaired transport. The public npm
tarball SHA-256 was independently recomputed as
`7d7682690c9a55a502575e78ad4fb70fccb4e54d4e8a8b033dd4cf3bf8cddc43`,
matching the verified release-candidate archive. The original `0.1.0`
filesystem proof above remains historical evidence rather than being rewritten.
The updated Recon rail then invoked the public `0.1.1` package twice against
the same isolated filesystem store, reserved consecutive `v3` and `v4` runs,
resolved all four locations for both, retained the support bytes, excluded the
unreadable archive, and produced identical primary-result digests. Google Drive
was not mutated by this repository follow-up.
