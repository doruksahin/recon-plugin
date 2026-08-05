---
date: '2026-08-05'
governs:
- tools/version-review.py
- tools/test-version-review.sh
- docs/system-map.html
id: SPEC-01KZ8CCYYG3B45TDJEW5MD1AT1
references:
- ADR-01KZ0ZK4WYVWRY0WJM2CZ7ZS8C
- SPEC-01KZ7E7FXK0T0W83PKGWPMC0ZW
- SPEC-01KZ8AXYBMF90CGY9554YDEJPZ
status: implemented
---

# SPEC-01KZ8CCYYG3B45TDJEW5MD1AT1 Version Review YAML Date Compatibility

## Overview

On 2026-08-05, retrying ATT-4845 capture after the timestamp-compatibility fix
reached the runtime-produced `triage/jira/post-gate.yaml`, whose canonical
unquoted scalar is `date: 2026-08-05`. PyYAML materializes that timestamp-tag
scalar as an exact `datetime.date`, while `parse_post_gate` passes it to the
string-only `require_nonempty` validator. Capture therefore exits 2 with
`workspace post-gate date must be a non-empty string` before writing a review
run, even though the producer text has the required date shape.

**Falsifiable claim:** for a workspace whose posting-gate record contains the
actual unquoted producer date, capture accepts an exact PyYAML `datetime.date`,
normalizes it to canonical `YYYY-MM-DD`, and completes the existing full
capture path. It continues to reject impossible, noncanonical, malformed,
datetime, and unrelated values before creating the requested run.

This is a second producer/consumer field-integration fix within the lifecycle
owned by `SPEC-01KZ7E7FXK0T0W83PKGWPMC0ZW` and follows the timestamp
normalization boundary in `SPEC-01KZ8AXYBMF90CGY9554YDEJPZ`. It does not alter
timestamp validation, capture contents, storage identity, privacy verification,
Jira boundaries, lifecycle state, plugin version, or live ATT-4845/private
review evidence. Isolated controls prove only this bounded rail behavior.

## Technical Design

Add one centralized strict date validator beside `require_timestamp`. It
accepts only canonical `YYYY-MM-DD` strings or values whose concrete type is
exactly `datetime.date`; it explicitly excludes `datetime.datetime`, whose
subclass relationship would otherwise make it date-like. Strings are parsed
with the standard library and must round-trip byte-for-byte so impossible and
noncanonical calendar values fail. Valid values return one canonical string.

`parse_post_gate` assigns that canonical return value to the parsed `date`
field before its semantic checks and before capture retains the artifact. No
generic recursive YAML coercion is introduced, and no unrelated fields change
their accepted types. The stable field-specific failure diagnostic is
`workspace post-gate date must be YYYY-MM-DD`.

All existing validation continues before destination creation. Timestamp,
private-repository, identity, symlink, overlap, Jira-mutation, lifecycle, hash,
and immutable-write behavior stays unchanged.

| Decision | Contract |
| --- | --- |
| Trigger | The version-review consumer validates the posting-gate `date` after PyYAML loading. |
| Inputs | Canonical date string or concrete PyYAML `datetime.date`. |
| Output | Canonical `YYYY-MM-DD` string. |
| Freedom | No caller judgment; one deterministic normalization path. |
| Side effects | None in the validator; capture writes only after every existing precondition passes. |
| Failure | Exit 2 through `ReviewError` with the field-specific diagnostic. |
| Verification | Actual unquoted producer fixture, strict negative matrix, successful full capture, no-run assertions, and repository commit gate. |

## Testing Strategy

Update the isolated posting-gate producer in `tools/test-version-review.sh` to
write the date scalar unquoted exactly as Recon runtime does. Assert directly
that `yaml.safe_load` returns concrete `datetime.date`, then let the ordinary
complete lifecycle capture that workspace successfully and verify the copied
posting-gate document still represents the same canonical date.

Add capture controls for an impossible calendar date, noncanonical string,
malformed string, YAML datetime, and unrelated scalar types. Each must exit 2
with the date diagnostic and leave no requested run. Retain the timestamp,
privacy, identity, Jira, lifecycle, integrity, no-overwrite, and cleanup matrix
unchanged. Run the focused version-review control, Decree lint/progress/intent
checks, generated Decree mirrors, and `bash tools/pre-commit-check.sh`.

## Acceptance Criteria

- [x] A centralized strict date validator canonicalizes exact `YYYY-MM-DD` strings and concrete `datetime.date` values to strings.
- [x] The validator rejects impossible, noncanonical, malformed, datetime, and unrelated values with the stable date diagnostic.
- [x] The full lifecycle fixture uses the actual unquoted producer posting-gate date, proves PyYAML returns `datetime.date`, and completes capture.
- [x] Every failed date capture leaves no run destination and preserves timestamp, privacy, identity, Jira, lifecycle, and integrity controls.
- [x] `bash tools/test-version-review.sh` and `bash tools/pre-commit-check.sh` pass.
- [x] Decree lint, progress, intent-check, generated index, and completion report agree with the implemented change.
- [x] No runtime workspace, private review repository, release/version, installed plugin, Jira issue, or published artifact is mutated.
