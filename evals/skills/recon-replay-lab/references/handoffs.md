# Replay laboratory handoffs

Load only the template needed for the current boundary. Replace every angle
bracket value with observed data. Do not omit paths, state, stop conditions, or
the return contract.

## Start: operator to fresh replay context

```text
Replay prepared

Case: <case-id> (<ticket>)
State: PREPARED
Run: <absolute-run-dir>
Target: <repository-name>@<commit>
Submission: <absolute-run-dir>/submission/triage.yaml

What is frozen:
- Sanitized ticket snapshot: <ticket-sha256>
- Recon triage skill snapshot: <skill-sha256>
- Target repository: exact commit above

What is excluded:
- The scoring oracle
- Live Jira access and all external mutations
- Prior conversation conclusions

Do this next:
1. Open a fresh LLM conversation with <absolute-run-dir> as its working directory.
2. Paste the prompt between the markers.

--- fresh-context prompt ---
Work only inside <absolute-run-dir>.
Read REPLAY.md first and follow it exactly.
Do not inspect paths outside this directory, contact Jira, search for an oracle,
or score your own output. Write only submission/triage.yaml. Copy exact
replay-only values from verifier/replay-owner-identities.json; never guess a
Jira account ID. Retain the generic decision audit required by the bundled
skill and map every blocking OPEN decision to one atomic blocker. Run
`python3 verifier/verify-submission.py` until it exits 0.
Only then return the exact handoff required by REPLAY.md and stop.
--- end prompt ---

Return here with the fresh context's handoff. The run directory is the only
handle the operator needs. I will derive state and evaluate after it returns.

STOP: the operator context must not author the submission.
```

## Resume: one operator context to another

```text
Resume Recon replay

Run: <absolute-run-dir>
Last derived state: <PREPARED|SUBMITTED|SCORED>
Retained artifacts: <paths-or-none>

First action:
python3 tools/replay-ticket.py state <absolute-run-dir>

Route only from that output. Evaluate only SUBMITTED. Never overwrite SCORED.
Use $recon-replay-lab and report the observed result, evidence boundary, and
exact next action.
```

## Comparison: evaluator to iteration owner

```text
Replay comparison handoff

Case: <case-id>
Baseline run: <absolute-path> — <score>, <matched>/<total>, skill <sha256>
Candidate run: <absolute-path> — <score>, <matched>/<total>, skill <sha256>
Known execution metadata: <models-hosts-run-count-or-unknown>
Retained evidence: <result-and-score-paths>

Observed change: <artifact-level delta>
Claim allowed: <bounded evidence statement>
Not demonstrated: <untested dimensions>
Next action: <repeat|inspect missed decision|revise skill|add case|independent review>
```
