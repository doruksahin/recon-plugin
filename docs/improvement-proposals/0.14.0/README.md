# v0.14.0 proposal cohort

> Historical proposed records retained for audit; this released-version cohort is closed to new intake.

- **Cohort status:** historical proposed
- **Opened:** 2026-08-01

| Proposal | Status | Prio | One-liner |
| --- | --- | --- | --- |
| [validate-triage-yaml](validate-triage-yaml/README.md) | proposed | P1 | Schema + regex lint for triage.yaml: rule-7 identifier bans, length caps, ask shape |
| [deterministic-decree-routing](deterministic-decree-routing/README.md) | proposed (policy needed) | P1 | Apply Decree routes from typed facts with a total, mechanically tested decision table |
| [render-dossier-rail](render-dossier-rail/README.md) | proposed (after schemas) | P1 | Render dossiers from artifacts; let the model author only headline and lede |
| [slop-lint](slop-lint/README.md) | proposed | P3 | Banned-phrase denylist + structural caps on the remaining free-text slots |
| [golden-fixtures](golden-fixtures/README.md) | proposed | P3 | Canned ticket.json fixtures + golden-output diffs; regression-test the pipeline |
| [credential-preflight](credential-preflight/README.md) | proposed | P1 | GET /myself before the ticket fetch; expired tokens fail loudly with a fix |
| [owner-resolution-order](owner-resolution-order/README.md) | proposed | P2 | Resolve accountIds from ticket data first; user search only as fallback |
| [answered-blocker-rule](answered-blocker-rule/README.md) | proposed | P2 | A reply closes a blocker only if it supplies the asked value; delegation ≠ answer |
| [evidence-ok-tristate](evidence-ok-tristate/README.md) | proposed | P2 | Split evidence_ok into true / auth-walled / broken; stop the permanent false flag |
| [step0-run-identity](step0-run-identity/README.md) | proposed | P3 | Key the fresh-workspace guard on a run token, not elapsed time |
| [jira-api-v3-search](jira-api-v3-search/README.md) | proposed | P3 | Migrate search references to /rest/api/3/search/jql; v2 search is removed |
| [jira-delivery-rail](jira-delivery-rail/README.md) | proposed (dedicated release) | P1 | Bind Jira approval to exact bytes, then deliver attachments and one comment idempotently |
