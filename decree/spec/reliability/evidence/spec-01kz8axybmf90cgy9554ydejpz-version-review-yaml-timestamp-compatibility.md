---
date: '2026-08-05'
governs:
- tools/version-review.py
- tools/test-version-review.sh
id: SPEC-01KZ8AXYBMF90CGY9554YDEJPZ
references:
- ADR-01KZ0ZK4WYVWRY0WJM2CZ7ZS8C
- SPEC-01KZ7E7FXK0T0W83PKGWPMC0ZW
status: implemented
---

# SPEC-01KZ8AXYBMF90CGY9554YDEJPZ Version Review YAML Timestamp Compatibility

## Overview

On 2026-08-05, the ATT-4845 Recon workspace producer wrote the canonical YAML
scalar `started: 2026-08-05T06:08:33Z`. PyYAML materializes that unquoted
scalar as a timezone-aware `datetime`, while the version-review consumer
accepts only a matching Python string. `capture` therefore exits 2 with
`workspace meta.started must be UTC YYYY-MM-DDTHH:MM:SSZ` before writing a
review run, even though the producer text already has the required shape.

**Falsifiable claim:** for a workspace whose `meta.yaml` contains the actual
unquoted producer shape, capture accepts the timezone-aware UTC value,
canonicalizes the retained receipt value to `YYYY-MM-DDTHH:MM:SSZ`, and keeps
rejecting naive, non-UTC, fractional-second, date-only, malformed, and
noncanonical string values with the existing stable diagnostic.

This is a producer/consumer field integration fix within the lifecycle owned
by `SPEC-01KZ7E7FXK0T0W83PKGWPMC0ZW`. It does not change the capture allowlist,
storage identity, privacy verification, Jira boundary, lifecycle, plugin
version, or any live ATT-4845/private-review evidence. Passing isolated parser
and lifecycle controls proves only this bounded rail behavior; it does not
claim general Recon quality improvement.

## Technical Design

Keep `require_timestamp` as the sole timestamp-shape owner. It continues to
accept only canonical UTC strings, additionally accepts PyYAML `datetime`
objects only when they are timezone-aware, have a zero UTC offset, and contain
no fractional seconds, and returns one canonical `Z`-suffixed string. Parse
canonical strings with the standard library so impossible calendar or clock
values fail instead of passing a regular expression alone. A YAML `date` is
not a `datetime` and remains invalid.

Every timestamp validation call assigns the canonical return value into the
specific validated field before the document is retained or compared. This
keeps internal and written representations string-only even when an authored
or producer YAML scalar arrived as a PyYAML object. No generic recursive YAML
coercion is introduced, and unrelated fields retain their existing types.

The command interface, exit code 2, and diagnostic
`<label> must be UTC YYYY-MM-DDTHH:MM:SSZ` remain stable. All root, origin,
GitHub visibility, privacy, identity, symlink, overlap, Jira-mutation, hash,
and immutable-write checks remain unchanged.

| Decision | Contract |
| --- | --- |
| Trigger | A timestamp-owning version-review field is validated after PyYAML loading. |
| Inputs | Canonical UTC string or timezone-aware, exact-second UTC `datetime`. |
| Output | Canonical `YYYY-MM-DDTHH:MM:SSZ` string. |
| Freedom | No model or caller judgment; one deterministic normalization path. |
| Side effects | None in the validator; capture writes only after all existing preconditions pass. |
| Failure | Exit 2 through the existing `ReviewError` diagnostic for every rejected type/shape/value. |
| Verification | Actual unquoted producer fixture, strict negative timestamp matrix, full lifecycle, and repository commit gate. |

## Testing Strategy

Update the isolated workspace producer in `tools/test-version-review.sh` to
write `meta.yaml` with the timestamp scalar unquoted, matching Recon runtime
output rather than PyYAML's quoted-string serialization. The clean lifecycle
must capture that workspace and retain `receipt.source.started` as the exact
canonical string.

Add capture controls for a naive timestamp, non-zero UTC offset, fractional
seconds, date-only scalar, impossible canonical-looking string, malformed
string, and non-string value. Each must exit 2 with the timestamp diagnostic
and must not create the requested run destination. Retain the existing full
privacy, identity, Jira, lifecycle, integrity, no-overwrite, and cleanup
matrix unchanged.

Run the focused version-review control, Decree lint/progress/intent checks,
and `bash tools/pre-commit-check.sh`. The live ATT-4845 workspace and external
private review repository are out of scope and must remain untouched.

## Acceptance Criteria

- [x] `require_timestamp` returns canonical strings for valid canonical UTC strings and timezone-aware exact-second UTC PyYAML datetime values.
- [x] Timestamp validation rejects naive, non-UTC, fractional-second, date-only, impossible, malformed, noncanonical string, and non-string values with the stable diagnostic.
- [x] The isolated clean lifecycle uses an actual unquoted producer timestamp and retains the canonical string in the capture receipt.
- [x] Failed timestamp captures leave no run destination and do not weaken existing storage, privacy, identity, Jira, lifecycle, or integrity controls.
- [x] `bash tools/test-version-review.sh` and `bash tools/pre-commit-check.sh` pass.
- [x] Decree lint, progress, intent-check, generated index, and completion report agree with the implemented change.
- [x] No runtime workspace, private review repository, release/version, installed plugin, Jira issue, or published artifact is mutated.
