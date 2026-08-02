# Make proofshot the single repro runtime

> Run every repro under proofshot: action-log + video provenance; steps transcribed, not recalled

- **Status:** proposed
- **Priority:** P1
- **Theme:** determinism rail
- **Origin:** Skill-design review on 2 Aug 2026 — post-v0.15.0 audit of `recon-repro`
  found rule 1 ("never fabricate") enforced by instruction plus *post-hoc* structural
  checks only: the verifier proves the package is well-formed, not that the session
  happened. Evaluated proofshot (<https://github.com/AmElmo/proofshot>) as the
  recording runtime that closes the gap.
- **Depends on:** [verify-repro-evidence](../verify-repro-evidence/README.md) (shipped v0.15.0)

## Problem

v0.15.0's `verify-repro.sh` proves a repro package is *well-formed*: fixed
frontmatter, step/exhibit parity, in-workspace regular files, current-run mtimes,
byte-valid PNGs. It cannot prove the steps *happened*. The model performs actions,
then writes `repro.md` from recall; no record of the actual session exists. A
plausible-but-wrong package — steps reordered relative to what was really done, a
screenshot of an adjacent state, a step never performed — passes every check, and
all four consumers (gate, brief, dossier, PR) inherit it. Visual readback is a
model judgment with no artifact a human can audit.

Two secondary costs ride along. Repro is the most host-entangled stage — hosts.md
must map browser control per host. And the evidence a PM answers a blocker from is
still stills they interpolate between.

## Before (today)

```text
repro/repro.md: 3. Click the eye icon on Collection3's row → the tab strip
                   collapses   [exhibits/3-after.png]

$ bash recon/scripts/verify-repro.sh ATT-6002
verify: clean
```

The PNG is fresh, contained, and byte-valid — the rail is satisfied whether or
not step 3 was ever performed, and whether the screenshot shows the claimed
state or a neighboring one. Nothing recorded the session, so nothing can
disagree with the prose.

## After (proposed)

Every repro session runs inside a recorder: start → drive the UI → stop bundles
mechanical provenance into the workspace:

```text
repro/session/session.webm         0:42 — the full session, scrubbing viewer
repro/session/session-log.json     17 timestamped actions (click/fill/navigate/screenshot)
repro/session/console-output.log
repro/session/server.log
```

`repro.md` steps are **transcribed from the action log**, not recalled, and the
verifier gains a cross-check that fails exactly like its v0.15.0 diagnostics:

```text
$ bash recon/scripts/verify-repro.sh ATT-6002
REPRO: step 3 has no matching click action in session-log.json between steps 2 and 4
REPRO: exhibits/2-action.png not produced by a logged screenshot action
```

The delivery zip carries `session.webm`, so a PM answering a BLOCKED question
watches the anomaly happen instead of interpolating between stills. Console and
server logs are captured on every repro — "reproduced, and it also threw this
error" surfaces even when nobody was looking for it, and failed repros
(`failure_reason: mock-gap`) ship with the server log that proves it. hosts.md's
per-host browser mapping for repro collapses to one runtime: same CLI, identical
bundle, on Claude Code and Codex.

## Implementation sketch

- `doctor.sh` + `reconctl.sh` preflight: blocking check for a pinned proofshot
  version (team standardizes on the install; an absent binary fails preflight,
  it does not fall back — one path, one evidence shape).
- `recon/skills/recon-repro/SKILL.md`: rule 6's host-preview dance replaced by
  the recorder invocation; workflow steps 2/4 become start → drive → stop; step
  5 transcribes numbered steps from `session-log.json`.
- `recon/scripts/verify-repro.sh` engine: cross-check numbered steps and
  exhibits against logged actions and their timestamps (all within the run
  window); vendor a schema snapshot of `session-log.json` so upstream changes
  fail loudly.
- `recon/docs/registry.yaml` + pipeline.md artifact registry: register
  `repro/session/*`.
- `recon/scripts/package-artifacts.sh`: include `session.webm` in the delivery
  zip behind a size guard.
- `recon/skills/recon-report/SKILL.md` slot map: console-log excerpt + a
  video-in-bundle pointer (the webm never embeds — dossier stays under its size
  cap).
- `recon/docs/hosts.md`: delete the repro browser-capability mapping.
- Ships as `feat(repro)!` with a `BREAKING CHANGE:` footer — a new required
  runtime dependency and a stage-semantics change.

## Open questions

- Driving quality: the model must locate/click elements through agent-browser as
  reliably as through the native browser tools. Validate side-by-side on 2–3
  real tickets before cutting the release; this is the go/no-go.
- Video size vs Jira attachment limits — trim or drop the webm above a
  threshold? Keep it for failed repros (often the most valuable recording)?
- Loss of live watching on Claude (Browser pane) — accepted trade: the evidence
  audience is the PM/implementer/gate reviewer, who get video instead.
- Upstream maturity: pin the version and vendor the log schema; decide who owns
  bump reviews.
