# docs/agent-behavior/ — local editor contract

This folder defines how capable agents reason about, change, and evaluate Recon.
It is repository governance, not runtime documentation or motivational prose.
Keep every rule operational: it must change what evidence an agent collects,
what action it takes, or what claim it is allowed to make.

## Progressive disclosure

1. Read only [README.md](README.md) at entry.
2. Follow its routing table to one relevant principle or playbook.
3. Load an example only when a concrete precedent is needed.

Do not recursively read this tree. Principle and playbook leaves are linked
directly from the root router; examples are one deliberate catalog hop away.

## File roles

| Entry | Role |
| --- | --- |
| `README.md` | Mandatory compact contract and task router; the only file loaded unconditionally. |
| `principles/` | Stable decision rules: core mentality, evidence/claim boundaries, and skill-spectrum selection. |
| `playbooks/` | Task-specific execution protocols for iteration and demonstrations. |
| `examples/` | Optional evidence audits used to calibrate claims against real Recon history. |

## Curation rules

- Preserve the distinction between observed fact, inference, proposal, and
  demonstrated outcome.
- Do not add an abstract principle without a corresponding decision rule or
  required artifact.
- Do not manufacture a clean example. Use a real repository change and expose
  its evidence gaps as well as its strengths.
- Keep the root README as a router, not a summary of every leaf.
- Keep category entry files narrow. A rule has one owner and is linked, not
  duplicated, elsewhere.
- A change that weakens an evidence threshold must say which failure it permits
  and why that trade is acceptable.
