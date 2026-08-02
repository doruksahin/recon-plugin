# Recon pipeline — improvement ideas

Index of proposed improvements. One line per idea; open the folder for the concrete
before/after. Conventions and template: [CLAUDE.md](CLAUDE.md).

Most ideas here originate from the ATT-5107 triage run (1 Aug 2026), which hit an
expired token, a duplicate-account trap, auth-walled evidence links, a removed Jira
API, and a delegation-vs-answer judgment call — all in one run.

## Determinism rails

Move work from SKILL.md prose into scripts that fail. Goal: the only free text the
model writes is asks, detail packs, headline, lede — everything else is derived.

| Idea | Status | Prio | One-liner |
| --- | --- | --- | --- |
| [derive-disposition](derive-disposition/README.md) | shipped (v0.9.0) | P1 | Compute the verdict from the six checks by script; lint fails on mismatch |
| [validate-triage-yaml](validate-triage-yaml/README.md) | proposed | P1 | Schema + regex lint for triage.yaml: rule-7 identifier bans, length caps, ask shape |
| [verify-quotes](verify-quotes/README.md) | shipped (v0.9.0) | P1 | Type evidence lines; substring-check every quote against ticket.json |
| [render-comment](render-comment/README.md) | shipped (v0.9.0) | P2 | Generate comment.txt from triage.yaml by script — the model never writes it |
| [slop-lint](slop-lint/README.md) | proposed | P3 | Banned-phrase denylist + structural caps on the remaining free-text slots |
| [golden-fixtures](golden-fixtures/README.md) | proposed | P3 | Canned ticket.json fixtures + golden-output diffs; regression-test the pipeline |

## Operational robustness

Failure modes observed live that the skills don't handle or handle ambiguously.

| Idea | Status | Prio | One-liner |
| --- | --- | --- | --- |
| [doc-coherence-rail](doc-coherence-rail/README.md) | shipped (v0.9.0) | P1 | One owner per shared fact; check-coherence.sh fails commits whose mirrors drift |
| [governance-ux](governance-ux/README.md) | in-progress | P2 | One-time question and reports phrased as handoff outcomes; ladder demoted to internals |
| [help-doctor-skill](help-doctor-skill/README.md) | in-progress | P2 | recon-help + doctor.sh: orientation and setup checks, every fact derived live |
| [credential-preflight](credential-preflight/README.md) | proposed | P1 | GET /myself before the ticket fetch; expired tokens fail loudly with a fix |
| [owner-resolution-order](owner-resolution-order/README.md) | proposed | P2 | Resolve accountIds from ticket data first; user search only as fallback |
| [answered-blocker-rule](answered-blocker-rule/README.md) | proposed | P2 | A reply closes a blocker only if it supplies the asked value; delegation ≠ answer |
| [evidence-ok-tristate](evidence-ok-tristate/README.md) | proposed | P2 | Split evidence_ok into true / auth-walled / broken; stop the permanent false flag |
| [step0-run-identity](step0-run-identity/README.md) | proposed | P3 | Key the fresh-workspace guard on a run token, not elapsed time |
| [jira-api-v3-search](jira-api-v3-search/README.md) | proposed | P3 | Migrate search references to /rest/api/3/search/jql; v2 search is removed |
