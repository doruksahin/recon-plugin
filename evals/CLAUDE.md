# evals/ — repository-only outcome evaluation

Nothing here ships in the plugin. The laboratory freezes real inputs and
oracles for repository development; prepared runs must contain inputs only.

| Entry | Role |
| --- | --- |
| `AGENTS.md` | Concise agent router, real replay/improvement examples, and hard evaluation boundaries. |
| `README.md` | Progressive-disclosure entry point, operator commands, claim boundary, and case ledger. |
| `cases/` | Immutable real-ticket cases: sanitized replay inputs, separately disclosed scoring oracles, and scorer-control fixtures. |
| `skills/` | Repository-local LLM operator workflows; never shipped or added to plugin manifests. |
| `evidence/` | Immutable minimal scored-run captures for versioned improvement records; never contains a target export or oracle. |
