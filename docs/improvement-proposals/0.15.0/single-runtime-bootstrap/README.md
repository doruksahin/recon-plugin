# Resolve runtime context atomically

> Resolve host, capabilities, root, and preflight with one atomic bootstrap command

- **Status:** shipped (v0.15.0) — one pure-output command with no frozen runtime
  identity or context file
- **Priority:** P2
- **Theme:** operational robustness
- **Origin:** The 2 Aug 2026 audit found the same multi-call host bootstrap in
  seven pipeline and maintainer skills while `hosts.md` warns that shell calls
  may be isolated; `recon-help` already delegates the sequence to `doctor.sh`.

## Problem

In v0.14.1, seven pipeline and maintainer skills told the model to call root
resolution, host detection, surface detection, capability output, and preflight
separately, then retain the values. On hosts that isolated shell calls, later
commands had to pass or substitute the remembered values manually. The seven
repeated sequences could combine values from different overrides when the
environment changed between calls.

Runtime identity controls gates, publishing, file display, and invocation syntax;
mixed identity could produce a false capability claim.

## Before (v0.14.1)

```text
call 1: root            → /shared/recon
call 2: detect-host     → codex
call 3: detect-surface  → codex-app
call 4: capabilities    → publish_stable_url unavailable
call 5: preflight base  → PASS
model had to retain and propagate four values across isolated calls
```

The sequence itself had no identity tying those outputs together.

## After (implemented)

```text
$ bash recon/scripts/reconctl.sh start base
root: /shared/recon
host: codex
surface: codex-app
capability.publish_stable_url: unavailable
profile: base
preflight: PASS

$ bash tools/test-host-contract.sh
host contract: PASS

documented setup operations across seven skills: 35 → 7 (−80%)
```

This is a pure-output snapshot before the skill's first mutation. Later rails
continue detecting their current host/surface so legitimate cross-host continuation
and per-event provenance remain intact.

Success means one command precedes mutation in seven pipeline/maintainer skills,
Recon Help continues delegating to its doctor rail, and host-contract tests prove
atomic output, zero workspace mutation, conservative ambiguity, and later-host
provenance re-detection.

## Implementation sketch

- Add a `start <profile>` operation to `reconctl.sh` that resolves identity once,
  prints stable machine-readable fields, and runs the matching preflight.
- Replace seven repeated Host setup blocks with the single command and the one
  remaining host-native interaction rule in the seven affected pipeline and
  maintainer skills.
- Extend host-contract tests with environment changes between scalar calls and an
  atomic-start comparison.

Implemented under
*SPEC-01KZ14Q6A2WB6J6TTX3XWQC5QJ Recon 0.15.0 Verified Handoff Chain*.

## Decision note

- `preflight` already printed root, host, and surface, so the incremental value
  was one coherent capability snapshot and a 35→7 setup-operation reduction.
  Agent review accepted it only as a narrow companion to the P1 handoff gates.
