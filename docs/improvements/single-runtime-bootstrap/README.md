# Resolve runtime context atomically

> Resolve host, capabilities, root, and preflight with one atomic bootstrap command

- **Status:** in-progress — narrowed to one pure-output command with no frozen
  runtime identity or context file
- **Priority:** P2
- **Theme:** operational robustness
- **Origin:** The 2 Aug 2026 audit found the same multi-call host bootstrap in
  seven stage skills while `hosts.md` warns that shell calls may be isolated;
  `recon-help` already delegates the sequence to `doctor.sh`.

## Problem

Every skill tells the model to call root resolution, host detection, surface
detection, capability output, and preflight separately, then retain the values.
On hosts that isolate shell calls, later commands must manually pass or substitute
the remembered values. The sequence is repeated eight times and can combine values
from different overrides if the environment changes between calls.

Runtime identity controls gates, publishing, file display, and invocation syntax;
mixed identity can produce a false capability claim.

## Before (today)

```text
call 1: root            → /shared/recon
call 2: detect-host     → codex
call 3: detect-surface  → codex-app
call 4: capabilities    → publish_stable_url unavailable
call 5: preflight base  → PASS
model must retain and propagate four values across isolated calls
```

The sequence itself has no identity tying those outputs together.

## After (proposed)

```text
$ recon runtime start base
root: /shared/recon
host: codex
surface: codex-app
capability.publish_stable_url: unavailable
preflight: PASS
```

This is a pure-output snapshot before the skill's first mutation. Later rails
continue detecting their current host/surface so legitimate cross-host continuation
and per-event provenance remain intact.

Success means one command precedes mutation, all eight skills share the same
one-line bootstrap, and host-contract tests cover override changes and isolation.

## Implementation sketch

- Add a `start <profile>` operation to `reconctl.sh` that resolves identity once,
  prints stable machine-readable fields, and runs the matching preflight.
- Replace eight repeated Host setup blocks with the single command and the one
  remaining host-native interaction rule in the seven affected stage skills.
- Extend host-contract tests with environment changes between scalar calls and an
  atomic-start comparison.

## Open questions

- `preflight` already prints root, host, and surface; the only incremental value is
  including capabilities in the same call. Reject this proposal if that one-call
  reduction does not justify another public command.
