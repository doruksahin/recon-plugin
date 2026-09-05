# Optional task-packet storage

Recon can save an already-rendered current run through the published
`@doruksahin/task-packet-store@0.1.1` CLI. This is an explicit optional
delivery. It does not publish a host artifact, post to Jira, or grant either
approval.

## Command

Use the current ticket workspace as `--source`, not its `report/` directory.
That includes the dossier and registered supporting evidence while the rail
prunes the unreadable top-level `runs/` archive before traversal. Before any
run is reserved, the package validates the store through `doctor`; for a
filesystem store, Recon rejects a packet destination that is equal to, inside,
or an ancestor of the source workspace, including through symlink aliases.
Current-run traversal must finish cleanly before staging or reservation, so an
unreadable supporting-evidence directory cannot be silently omitted.

```bash
bash recon/scripts/store-dossier.sh \
  --store /absolute/path/store.json \
  --ticket PROJ-123 \
  --source /absolute/path/to/recon-root/PROJ-123
```

All three paths are explicit: the store config and source must be absolute,
and the source basename and `meta.yaml` ticket must equal `--ticket`. The
workspace must already contain regular `meta.yaml`, `triage/triage.yaml`, and
`report/dossier.html` files. The rail validates a pruned temporary copy with
`lint-workspace.sh`; it never writes package state or a receipt into the Recon
workspace.

The package owns the store JSON schema and its validation. Use the same
credential-free config already selected for the workflow. The `fs` driver
needs only its persistent root. The `gdrive` driver reads exactly one of
`PACKET_STORE_DRIVE_SERVICE_ACCOUNT_CREDENTIALS` or
`PACKET_STORE_DRIVE_TOKEN` from the environment; never put a credential in
the config, command, workspace, or repository.

Internally the rail runs the exact public package pin through npm:

```bash
env 'npm_config_@doruksahin:registry=https://registry.npmjs.org/' \
  npm exec --yes --package=@doruksahin/task-packet-store@0.1.1 -- \
  task-packet-store <operation>
```

This one-off bootstrap requires Node.js 20 or newer. Drive additionally needs
the package's pinned rclone runtime. Recon has no transport branch: the same
`begin`, `checkpoint`, and `locate` calls serve both store drivers.

## Result contract

The command prints exactly one compact JSON object only after the complete
current run is checkpointed under `stages/10-recon/runs/vN/` and every
location lookup succeeds:

```json
{
  "schemaVersion": 1,
  "operation": "recon-dossier-store",
  "package": "@doruksahin/task-packet-store@0.1.1",
  "tool": "recon@0.21.0",
  "ticket": "PROJ-123",
  "stage": "10-recon",
  "version": "v1",
  "sourceDirectory": "/absolute/path/to/recon-root/PROJ-123",
  "primaryResult": "report/dossier.html",
  "lint": "lint: clean — 4 file(s), all registered",
  "checkpoint": {
    "version": "v1",
    "reason": "recon-dossier-rendered",
    "fileCount": 4,
    "inventorySha256": "<sha256>"
  },
  "locations": {
    "run": {"ticket": "PROJ-123", "driver": "fs", "relativePath": "stages/10-recon/runs/v1", "kind": "directory", "location": "/persistent/store/PROJ-123/stages/10-recon/runs/v1"},
    "primary": {"ticket": "PROJ-123", "driver": "fs", "relativePath": "stages/10-recon/runs/v1/report/dossier.html", "kind": "file", "location": "/persistent/store/PROJ-123/stages/10-recon/runs/v1/report/dossier.html"},
    "runRecord": {"ticket": "PROJ-123", "driver": "fs", "relativePath": "stages/10-recon/runs/v1/run.md", "kind": "file", "location": "/persistent/store/PROJ-123/stages/10-recon/runs/v1/run.md"},
    "snapshot": {"ticket": "PROJ-123", "driver": "fs", "relativePath": "stages/10-recon/runs/v1/snapshot.json", "kind": "file", "location": "/persistent/store/PROJ-123/stages/10-recon/runs/v1/snapshot.json"}
  }
}
```

`locations.run` is the supporting-evidence root. Filesystem locations are
readable absolute paths. Drive locations are URLs for callers that already
have access; locating them does not change sharing permissions.

If validation, reservation, checkpointing, or any lookup fails, the command
exits nonzero, writes the phase diagnostic to stderr, and keeps stdout empty.
A failure after reservation can leave its `run.md` for audit, and a failure
after checkpoint can leave saved bytes, but neither state is reported as a
successful persistence receipt.

## Filesystem acceptance

Use a persistent `fs` store config and a neutral rendered workspace. Remove
Drive credentials and rclone from the acceptance environment, invoke the
command twice, and retain both JSON receipts. Verify:

1. the first receipt says `v1` and all four returned locations exist;
2. the saved primary and at least one support file match the source bytes;
3. no `runs/` directory from the source exists below the stored run;
4. `snapshot.json` lists the intended current-run files;
5. the second receipt says `v2`; and
6. the first run's bytes and locations are unchanged after the second save.

## Google Drive acceptance

Use the same rendered workspace and command with an existing valid `gdrive`
config whose prefix is isolated for acceptance. Supply exactly one package
credential variable in the environment and run the package's read-only
`doctor --store <absolute-config>` before mutation. Then:

1. invoke `store-dossier.sh` and require exit 0 plus one JSON receipt;
2. open or fetch the returned `locations.primary.location` and inspect the
   returned run folder for current-run support files, `run.md`, and
   `snapshot.json`;
3. invoke the identical command again and require the next `vN`;
4. re-open the first receipt's four locations and verify the original bytes;
5. inject an invalid destination or revoke the acceptance credential and
   require nonzero exit with empty stdout.

Private acceptance owns the config, credential, isolated prefix, and retained
receipts. No remote Drive write is required by this repository's checks.
