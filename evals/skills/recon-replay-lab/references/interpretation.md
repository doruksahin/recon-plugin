# Interpret a retained replay result

Use only after `state` derives `SCORED`. The authoritative data is
`evaluation/result.json`; `evaluation/score.txt` is its human-readable trace.

## Read the result in this order

1. `artifact.status`: whether the submission passed Recon's production triage
   verifier. A failure means the artifact contract failed; decision quality was
   not evaluated.
2. `disposition.status`: whether the submitted READY, BLOCKED, or NEEDS_INFO
   outcome matches the frozen case expectation.
3. `decision_coverage`: the maximum one-to-one match between required decisions
   and candidate blockers. `missed` names uncovered decisions. `overloaded`
   names one blocker that resembles multiple independent decisions but can earn
   credit for only one.
4. `score` and `score_exit`: PASS/0 only when artifact, disposition, and all
   decisions pass; FAIL/1 otherwise.
5. `candidate_sha256` and `score_sha256`: integrity links checked whenever state
   is derived again.

## Map outcome to next action

| Observed outcome | Meaning | Concrete next action |
| --- | --- | --- |
| Artifact FAIL | The generated `triage.yaml` violates the production schema or evidence rules. | Keep the run unchanged. Inspect `score.txt`, revise the relevant replay/triage instruction, and prepare a new run. |
| Disposition FAIL | The artifact is valid but chose the wrong gate outcome for this frozen case. | Inspect the check evidence and rerun from a new prepared directory after a bounded skill revision. |
| Coverage FAIL with `missed` | A case decision has no distinct blocker. | Inspect the named decision and the candidate blocker text; revise the skill to preserve decision atomicity, then start a new run. |
| Coverage FAIL with `overloaded` | One blocker merged independent product decisions. | Split the questions in the skill/output contract; verify the same case changes from the retained baseline in a fresh context. |
| PASS | This run covered this case under this skill snapshot. | Repeat in fresh contexts and add representative cases before making cross-model, cross-host, or general-quality claims. |

## Explain the before/after user experience

Before the state rail, the operator had to remember whether another LLM had
finished, manually select a candidate path, invoke `score`, and preserve its
terminal output. A handoff could lose the case, next command, or result.

After the state rail, the run directory is the single handle. `state` derives
the stop and next action from files; `evaluate` preserves both the machine
result and human trace; another context can resume without prior chat history.
The bundled verifier now stops invalid artifacts before evaluation: a failed
verifier is a contract failure, not decision-coverage evidence. This
demonstrates workflow mechanics when controls pass. It does not by itself
demonstrate better generative judgment.

## Bound the claim

- A clean fixture proves scorer or state mechanics (E2), not model quality.
- A retained fresh-context run on ATT-4845 supports a task-specific outcome
  statement (E3) only when model, host, skill hash, and intervention are kept.
- One pass does not prove repeatability, portability, or “works for any task.”
- General workflow claims require representative real cases, repeated fresh
  runs, fixed rubrics, raw outputs, and independent review.
