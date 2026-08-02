# Help that cannot drift: recon-help + doctor.sh

> Orientation + setup doctor; every printed fact derived live, none restated

- **Status:** shipped (v0.10.0) — implemented 2 Aug 2026 (`recon/scripts/doctor.sh`,
  `recon/skills/recon-help/`, stage legend added to pipeline.md, coherence pass 3
  extended: every skill must appear in README.md and plugin.json)
- **Priority:** P2
- **Theme:** operational robustness
- **Origin:** 2 Aug 2026 — preparing to share the plugin with colleagues: the
  five skills had descriptions but nothing answered "what is this, what do I
  type, does my setup work" from inside Claude Code; the #1 observed onboarding
  cliff (an expired Jira token, 1 Aug) failed with a misleading error.

## Problem

Every other plugin in the marketplace has a menu/entry skill; recon had none —
but recon's need is orientation + setup verification, not command selection
(there is only one command). And a naive help page would be a new drift
surface: a hand-written skill list, version, and setup instructions that rot
the moment anything changes.

## Before (2 Aug)

A colleague installing the plugin sees five slash commands and has to read the
repo to learn: run `recon-triage` first, everything else chains; `~/.config/jira/env`
must exist with a valid token (failure mode: "Issue does not exist or you do
not have permission" — actually an expired token); a handoff-style question
will appear mid-run once.

## After (implemented)

`/recon:recon-help` presents `doctor.sh` output — a rail whose every line is
derived at run time:

- version — read from the installed `plugin.json`
- skill list — generated from each sibling SKILL.md's own frontmatter
  `description` (the owner of "when to use"); a new skill appears automatically
- Jira credentials — env file present AND `GET /myself` succeeds; 401 prints
  the regenerate-token remediation (industry pattern: `doctor` beats `help`)
- handoff style — `detect-governance.sh` reused verbatim, phrased fence-safe
- stage legend — now owned by pipeline.md's state machine section; the skill
  quotes it

Anti-drift guarantees:

- SKILL.md rule 1: facts come from the rail, never restated from memory.
- `check-coherence.sh` pass 3 extended: every `recon/skills/*` directory must
  appear in README.md and be registered in plugin.json `skills[]` — a new,
  undiscoverable skill fails the commit (proved live: the checker named the
  three missing mentions of recon-help/doctor.sh before they were written).

## Implementation sketch

Shipped as described. Follow-up candidates:

- `doctor.sh --json` for scripted use once golden-fixtures lands.
- The in-run credential preflight ([credential-preflight](../credential-preflight/README.md))
  can now reuse doctor's Jira check logic when it moves into triage step 1.

## Open questions

- None.
