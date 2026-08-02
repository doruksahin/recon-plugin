# Speak handoff outcomes, not governance configs

> One-time question and reports phrased as outcomes; ladder demoted to internals

- **Status:** shipped (v0.10.0) — implemented 2 Aug 2026 (recon-discovery step 4 question
  rewritten, `Handoff style:` report line + source-token mapping table, README
  story restructured)
- **Priority:** P2
- **Theme:** operational robustness
- **Origin:** 2 Aug 2026 — explaining the governance selection to the developer
  took a three-layer precedence ladder, seven `source` tokens, and the words
  "governance", "probe", and "undecided"; the developer's actual question is just
  "do I get decree docs or a plain brief?".

## Problem

The pipeline enforces rule 8 on every question it posts to Jira — options as
user-observable outcomes, internal identifiers banned — but its own one question
to the developer offered three config enums (`none | decree | auto`), and the
discovery report printed raw machine tokens (`governance:
none/probe-detected-no-choice`). The state was also invisible: nothing told the
developer what was resolved or how to change it without reading the scripts.

## Before (2 Aug)

The one-time question:

> "decree is set up in this repo — route recon runs through it?"
> Options: `Use it` / `Don't use it` / `Per repo (auto)`

The report line:

```
Route: brief (rule 3, governance: decree/config) — see route/routing.yaml
```

Neither says what the developer *gets*, and `decree/config` is pipeline
vocabulary standing where an answer should be.

## After (implemented)

The question describes the outcome of each choice:

> "This repo has decree set up. When a ticket is approved, how should recon
> hand off the work?"
> - **Write decree docs (Recommended)** — approved tickets route into this repo's decree flow
> - **Plain briefs** — a standalone implementation brief; decree never involved
> - **Follow each repo** — decree docs where set up, plain briefs everywhere else

The report gains a plain-words line (raw tokens kept as parenthetical evidence),
translated by a mechanical mapping table in the SKILL.md — including
fence-safe phrasings that never name the tool when governance resolved to `none`:

```
Route: brief (rule 3) — see route/routing.yaml
Handoff style: decree docs — your standing choice (change anytime: set-governance.sh) (governance: decree/config)
```

README: the user-facing story is one sentence (ask once, saved, change anytime);
the env var and precedence ladder moved to an "Internals" paragraph. No script
changed — `detect-governance.sh` output stays parse-stable; only the human
surface was rewritten.

## Implementation sketch

Shipped as described. Candidate follow-up: a `/recon:handoff-style` status
command (print the resolved style + one-line change instruction) so the state is
inspectable outside a run.

## Open questions

- Should the `source` tokens `env-decree-but-unavailable` /
  `config-decree-but-unavailable` be renamed to tool-neutral forms? They name
  decree while resolving to `none`, but only fire for a developer who explicitly
  chose decree — the fence's spirit (never expose vocabulary to the un-opted-in)
  holds. Rename only if a second adapter ever ships.
