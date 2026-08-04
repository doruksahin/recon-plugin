#!/usr/bin/env python3
"""Render the source-derived real-ticket replay laboratory operator report."""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "docs" / "replay-lab-report.html"
CASE_DIR = ROOT / "evals" / "cases" / "att-4845-pre-comment"
REPLAY_TOOL = ROOT / "tools" / "replay-ticket.py"


STYLE = r"""
:root {
  color-scheme: dark;
  --bg: #08111e;
  --panel: #101c2b;
  --panel-2: #142438;
  --line: #29415f;
  --text: #edf5ff;
  --muted: #a6b6c9;
  --blue: #79b8ff;
  --cyan: #59e1d8;
  --green: #62d995;
  --amber: #f5c56b;
  --red: #ff8585;
  --violet: #c8a8ff;
  --shadow: 0 18px 48px rgba(0, 0, 0, .28);
  --radius: 18px;
}
* { box-sizing: border-box; }
html { scroll-behavior: smooth; }
body {
  margin: 0;
  background:
    radial-gradient(circle at 85% 0%, rgba(121,184,255,.14), transparent 30rem),
    radial-gradient(circle at 10% 28%, rgba(89,225,216,.08), transparent 32rem),
    var(--bg);
  color: var(--text);
  font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  line-height: 1.62;
}
a { color: var(--blue); text-underline-offset: 3px; }
code, pre { font-family: "SFMono-Regular", Consolas, "Liberation Mono", monospace; }
code { color: #d9eaff; }
.shell { display: grid; grid-template-columns: 250px minmax(0, 1fr); min-height: 100vh; }
.sidebar {
  position: sticky; top: 0; height: 100vh; padding: 28px 22px;
  border-right: 1px solid var(--line); background: rgba(8,17,30,.9); backdrop-filter: blur(18px);
}
.brand { display: flex; align-items: center; gap: 12px; margin-bottom: 30px; }
.mark { width: 36px; height: 36px; border-radius: 11px; display: grid; place-items: center;
  color: #06101a; font-weight: 900; background: linear-gradient(135deg, var(--cyan), var(--blue)); }
.brand strong { display: block; letter-spacing: -.02em; }
.brand span { display: block; color: var(--muted); font-size: .74rem; text-transform: uppercase; letter-spacing: .1em; }
nav a { display: block; padding: 8px 11px; margin: 3px 0; border-radius: 9px; color: var(--muted); text-decoration: none; font-size: .9rem; }
nav a:hover, nav a:focus { color: var(--text); background: var(--panel); }
.sidebar-note { position: absolute; left: 22px; right: 22px; bottom: 22px; color: var(--muted); font-size: .74rem; }
main { width: min(1180px, 100%); margin: 0 auto; padding: 52px 48px 100px; }
.eyebrow { color: var(--cyan); font-size: .78rem; font-weight: 800; letter-spacing: .13em; text-transform: uppercase; }
h1 { max-width: 920px; margin: 12px 0 18px; font-size: clamp(2.5rem, 5vw, 5.2rem); line-height: .98; letter-spacing: -.06em; }
h2 { margin: 0 0 18px; font-size: clamp(1.65rem, 3vw, 2.5rem); letter-spacing: -.035em; }
h3 { margin: 0 0 10px; font-size: 1.08rem; }
p { margin: 0 0 16px; }
.lede { max-width: 860px; color: #c8d6e7; font-size: 1.18rem; }
.hero { padding-bottom: 54px; border-bottom: 1px solid var(--line); }
.hero-grid, .two, .three { display: grid; gap: 18px; }
.hero-grid { grid-template-columns: 1.45fr .8fr; margin-top: 30px; }
.two { grid-template-columns: repeat(2, minmax(0, 1fr)); }
.three { grid-template-columns: repeat(3, minmax(0, 1fr)); }
.card { background: linear-gradient(155deg, rgba(20,36,56,.94), rgba(13,25,40,.96)); border: 1px solid var(--line); border-radius: var(--radius); padding: 22px; box-shadow: var(--shadow); }
.card.flat { box-shadow: none; }
.metric { font-size: 2rem; font-weight: 850; letter-spacing: -.04em; }
.muted { color: var(--muted); }
.good { color: var(--green); }
.bad { color: var(--red); }
.warn { color: var(--amber); }
.blue { color: var(--blue); }
.tag { display: inline-flex; align-items: center; border: 1px solid var(--line); border-radius: 999px; padding: 5px 10px; margin: 4px 5px 4px 0; color: var(--muted); font-size: .75rem; }
.tag.good { border-color: rgba(98,217,149,.4); color: var(--green); }
.tag.warn { border-color: rgba(245,197,107,.4); color: var(--amber); }
.tag.bad { border-color: rgba(255,133,133,.4); color: var(--red); }
section { padding: 62px 0 0; scroll-margin-top: 24px; }
.section-head { display: flex; justify-content: space-between; gap: 24px; align-items: end; margin-bottom: 22px; }
.section-head p { max-width: 650px; color: var(--muted); }
.callout { border-left: 3px solid var(--cyan); padding: 16px 18px; background: rgba(89,225,216,.06); border-radius: 0 12px 12px 0; }
.callout.warn { border-left-color: var(--amber); background: rgba(245,197,107,.07); }
.callout.bad { border-left-color: var(--red); background: rgba(255,133,133,.07); }
.tree { white-space: pre; overflow: auto; margin: 0; padding: 20px; color: #cde4ff; background: #07101b; border: 1px solid #213952; border-radius: 14px; font-size: .83rem; line-height: 1.58; }
.tree .owned { color: var(--cyan); }
.legend { margin-top: 12px; color: var(--muted); font-size: .8rem; }
.ownership { width: 100%; border-collapse: collapse; font-size: .9rem; }
.ownership th, .ownership td { text-align: left; vertical-align: top; padding: 13px 12px; border-bottom: 1px solid var(--line); }
.ownership th { color: var(--muted); font-size: .73rem; text-transform: uppercase; letter-spacing: .08em; }
.ownership tr:last-child td { border-bottom: 0; }
.flow { display: grid; grid-template-columns: repeat(6, 1fr); gap: 10px; align-items: stretch; }
.step { position: relative; min-height: 150px; padding: 16px; border: 1px solid var(--line); border-radius: 14px; background: var(--panel); }
.step::after { content: "→"; position: absolute; top: 50%; right: -18px; z-index: 2; color: var(--cyan); font-weight: 900; }
.step:last-child::after { display: none; }
.step b { display: block; margin-bottom: 8px; color: var(--blue); }
.step span { color: var(--muted); font-size: .82rem; }
.decision { position: relative; padding-left: 54px; }
.decision .number { position: absolute; left: 18px; top: 18px; width: 27px; height: 27px; display: grid; place-items: center; border-radius: 8px; background: rgba(121,184,255,.14); color: var(--blue); font-weight: 800; }
.compare { display: grid; grid-template-columns: 1fr 1fr; gap: 18px; }
.compare .card { overflow: hidden; }
.compare-head { display: flex; justify-content: space-between; gap: 14px; align-items: center; margin-bottom: 12px; }
.terminal { position: relative; margin: 0; padding: 18px; min-height: 220px; overflow: auto; white-space: pre-wrap; color: #d7e7f9; background: #050b12; border: 1px solid #203448; border-radius: 12px; font-size: .8rem; line-height: 1.55; }
.copy { border: 1px solid var(--line); border-radius: 8px; padding: 6px 9px; background: transparent; color: var(--muted); cursor: pointer; }
.copy:hover { color: var(--text); border-color: var(--blue); }
.runbook { counter-reset: runstep; }
.runstep { position: relative; padding: 22px 22px 22px 74px; margin-bottom: 14px; border: 1px solid var(--line); border-radius: 16px; background: var(--panel); }
.runstep::before { counter-increment: runstep; content: counter(runstep); position: absolute; left: 22px; top: 22px; width: 34px; height: 34px; display: grid; place-items: center; border-radius: 11px; color: #06101a; background: var(--cyan); font-weight: 900; }
.command { position: relative; margin: 12px 0 0; padding: 15px 52px 15px 15px; overflow: auto; white-space: pre-wrap; background: #050b12; border: 1px solid #203448; border-radius: 11px; color: #d7e7f9; font-size: .8rem; }
.command .copy { position: absolute; top: 8px; right: 8px; }
.matching { display: grid; grid-template-columns: 1fr 80px 1fr; align-items: center; gap: 12px; }
.node { padding: 11px 13px; margin: 7px 0; border: 1px solid var(--line); border-radius: 10px; background: var(--panel-2); font-size: .84rem; }
.edges { text-align: center; color: var(--cyan); font-size: 1.5rem; line-height: 1.7; }
.integrity { display: grid; grid-template-columns: repeat(3, minmax(0,1fr)); gap: 14px; }
.integrity b { display: block; margin-bottom: 6px; color: var(--cyan); }
.scenario { border-top: 1px solid var(--line); padding: 18px 0; }
.scenario:first-child { border-top: 0; padding-top: 0; }
.scenario strong { color: var(--blue); }
.ref { display: inline-flex; min-width: 27px; justify-content: center; margin-left: 4px; padding: 1px 6px; border: 1px solid rgba(121,184,255,.4); border-radius: 999px; color: var(--blue); text-decoration: none; font-size: .67rem; vertical-align: super; }
.refs { list-style: none; padding: 0; }
.refs li { display: grid; grid-template-columns: 46px 1fr auto; gap: 12px; padding: 14px 0; border-bottom: 1px solid var(--line); }
.refs li:last-child { border-bottom: 0; }
.ref-id { color: var(--cyan); font-weight: 800; }
.hash { color: var(--muted); font-family: monospace; font-size: .75rem; }
.boundary { border: 1px solid rgba(245,197,107,.35); background: rgba(245,197,107,.06); }
footer { margin-top: 64px; padding-top: 26px; border-top: 1px solid var(--line); color: var(--muted); font-size: .8rem; }
@media (max-width: 1050px) {
  .shell { grid-template-columns: 1fr; }
  .sidebar { position: relative; width: 100%; height: auto; border-right: 0; border-bottom: 1px solid var(--line); }
  .sidebar nav { display: flex; flex-wrap: wrap; }
  .sidebar-note { display: none; }
  main { padding: 38px 28px 80px; }
  .flow { grid-template-columns: repeat(3, 1fr); }
  .step:nth-child(3)::after { display: none; }
}
@media (max-width: 720px) {
  main { padding: 30px 18px 64px; }
  h1 { font-size: 2.55rem; }
  .hero-grid, .two, .three, .compare, .integrity { grid-template-columns: 1fr; }
  .flow { grid-template-columns: 1fr; }
  .step { min-height: auto; }
  .step::after { content: "↓"; top: auto; bottom: -24px; right: 50%; }
  .step:nth-child(3)::after { display: block; }
  .matching { grid-template-columns: 1fr; }
  .edges { transform: rotate(90deg); height: 44px; }
  .section-head { display: block; }
  .refs li { grid-template-columns: 38px 1fr; }
  .hash { grid-column: 2; }
  .ownership { font-size: .78rem; }
  .ownership th, .ownership td { padding: 10px 7px; }
}
@media print {
  :root { color-scheme: light; --bg:#fff; --panel:#fff; --panel-2:#f4f7fa; --line:#ccd5df; --text:#122033; --muted:#536173; }
  body { background:#fff; }
  .shell { display:block; }
  .sidebar, .copy { display:none; }
  main { width:100%; padding:0; }
  .card, .step, .runstep { box-shadow:none; break-inside:avoid; }
  .terminal, .command, .tree { color:#152033; background:#f3f6f9; }
  a { color:#174f8b; }
}
"""


SCRIPT = r"""
document.querySelectorAll('[data-copy]').forEach((button) => {
  button.addEventListener('click', async () => {
    const target = document.getElementById(button.dataset.copy);
    try {
      await navigator.clipboard.writeText(target.innerText);
      const prior = button.textContent;
      button.textContent = 'Copied';
      setTimeout(() => { button.textContent = prior; }, 1200);
    } catch (_) {
      button.textContent = 'Select text';
    }
  });
});
"""


@dataclass(frozen=True)
class SourceRef:
    ref_id: str
    title: str
    path: str
    needle: str
    line: int
    digest: str


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_ref(ref_id: str, title: str, path: str, needle: str):
    absolute = ROOT / path
    text = absolute.read_text(encoding="utf-8")
    for number, line in enumerate(text.splitlines(), 1):
        if needle in line:
            return SourceRef(ref_id, title, path, needle, number, sha256(absolute))
    raise RuntimeError(f"reference needle not found in {path}: {needle}")


def run_evidence(args: list[str], expected_status: int):
    environment = os.environ.copy()
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    result = subprocess.run(
        [sys.executable, str(REPLAY_TOOL), *args],
        cwd=ROOT,
        env=environment,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    output = "\n".join(part.strip() for part in (result.stdout, result.stderr) if part.strip())
    if result.returncode != expected_status:
        raise RuntimeError(
            f"evidence command exited {result.returncode}, expected {expected_status}: "
            f"{' '.join(args)}\n{output}"
        )
    return result.returncode, output


def h(value):
    return html.escape(str(value), quote=True)


def ref_badge(ref_id):
    return f'<a class="ref" href="#ref-{h(ref_id.lower())}" aria-label="Reference {h(ref_id)}">{h(ref_id)}</a>'


def command_block(block_id, command):
    return (
        f'<div class="command" id="{h(block_id)}">{h(command)}'
        f'<button class="copy" data-copy="{h(block_id)}">Copy</button></div>'
    )


def extract_between(text, start, end):
    if start not in text or end not in text:
        raise RuntimeError(f"cannot extract generated report block: {start} … {end}")
    return text.split(start, 1)[1].split(end, 1)[0].strip()


def run_handoff_control():
    """Exercise PREPARED -> SUBMITTED -> SCORED without a model invocation."""
    with tempfile.TemporaryDirectory(prefix="recon-report-handoff-") as temp_name:
        temp = Path(temp_name)
        case_dir = temp / CASE_DIR.name
        shutil.copytree(CASE_DIR, case_dir)
        manifest_path = case_dir / "case.json"
        manifest = read_json(manifest_path)
        head = subprocess.run(
            ["git", "-C", str(ROOT), "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
        manifest["repository"] = {"name": "recon-plugin-control", "commit": head}
        manifest_path.write_text(
            json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
        )
        run_dir = temp / "run"
        run_evidence(
            ["prepare", str(case_dir), "--repo", str(ROOT), "--out", str(run_dir)],
            0,
        )
        _, prepared = run_evidence(
            ["state", str(run_dir), "--case", str(case_dir)], 0
        )
        shutil.copyfile(
            case_dir / "fixtures" / "atomic-pass.yaml",
            run_dir / "submission" / "triage.yaml",
        )
        verifier = subprocess.run(
            [sys.executable, str(run_dir / "verifier" / "verify-submission.py")],
            cwd=run_dir,
            capture_output=True,
            text=True,
        )
        if verifier.returncode != 0 or "replay verifier: clean" not in verifier.stdout:
            raise RuntimeError(
                "prepared verifier control failed: "
                + "\n".join(part for part in (verifier.stdout, verifier.stderr) if part)
            )
        _, submitted = run_evidence(
            ["state", str(run_dir), "--case", str(case_dir)], 0
        )
        evaluate_status, evaluated = run_evidence(
            ["evaluate", str(run_dir), "--case", str(case_dir)], 0
        )
        _, scored = run_evidence(
            ["state", str(run_dir), "--case", str(case_dir)], 0
        )
        outputs = tuple(
            output.replace(str(temp), "<isolated-control>")
            for output in (prepared, submitted, evaluated, scored)
        )
        return (*outputs, evaluate_status)


def render():
    manifest = read_json(CASE_DIR / "case.json")
    ticket = read_json(CASE_DIR / manifest["input"]["ticket"])
    oracle = read_json(CASE_DIR / manifest["oracle"])
    decisions = oracle["required_decisions"]
    calibration = oracle.get("calibration", [])
    total = len(decisions)
    ticket_key = manifest["source"]["ticket"]
    target_commit = manifest["repository"]["commit"]
    case_rel = "evals/cases/att-4845-pre-comment"
    atomic_rel = f"{case_rel}/fixtures/atomic-pass.yaml"
    combined_rel = f"{case_rel}/fixtures/combined-layout-fail.yaml"

    validate_status, validate_output = run_evidence(["validate", case_rel], 0)
    atomic_status, atomic_output = run_evidence(["score", case_rel, atomic_rel], 0)
    combined_status, combined_output = run_evidence(["score", case_rel, combined_rel], 1)
    prepared_output, submitted_output, evaluated_output, scored_output, evaluate_status = (
        run_handoff_control()
    )

    required_evidence = {
        "validate": (validate_output, f"{total} decision(s), oracle separated"),
        "atomic": (atomic_output, f"decision coverage: PASS — {total}/{total} distinct decisions"),
        "combined": (combined_output, "artifact: FAIL — production triage verifier exited 1"),
        "prepared": (prepared_output, "state: PREPARED"),
        "submitted": (submitted_output, "state: SUBMITTED"),
        "evaluated": (evaluated_output, "evaluate: retained"),
        "scored": (scored_output, "state: SCORED"),
    }
    for label, (output, token) in required_evidence.items():
        if token not in output:
            raise RuntimeError(f"{label} evidence lost required diagnostic: {token}")

    refs = [
        source_ref("R1", "Case identity, cutoff, input hash, and target commit", f"{case_rel}/case.json", '"snapshot_at"'),
        source_ref("R2", "Sanitized pre-comment Jira input", f"{case_rel}/input/ticket.json", '"description"'),
        source_ref("R3", "Calibrated scoring oracle", f"{case_rel}/oracle/decisions.json", '"calibration"'),
        source_ref("R4", "Case validation and hash checks", "tools/replay-ticket.py", "def validate_case"),
        source_ref("R5", "Atomic preparation and oracle exclusion", "tools/replay-ticket.py", "def prepare_case"),
        source_ref("R6", "One-to-one matching algorithm", "tools/replay-ticket.py", "def maximum_matching"),
        source_ref("R7", "Production-verifier-first score path", "tools/replay-ticket.py", "def analyze_case"),
        source_ref("R8", "Positive, negative, drift, and overwrite controls", "tools/test-replay-lab.sh", "combined-layout-fail.yaml"),
        source_ref("R9", "Bounded evidence and improvement rules", "docs/agent-behavior/README.md", "Do not claim improvement"),
        source_ref("R10", "Governing offline-validity technical design", "decree/spec/reliability/evidence/spec-01kz63vtj3dk28e7n5q1f9f6n8-recon-0-20-0-offline-valid-replay-verification.md", "Falsifiable claim"),
        source_ref("R11", "Observed ATT-4845 origin and concrete gap", "docs/improvement-proposals/0.19.0/real-ticket-replay-lab/README.md", "Recon blockers:"),
        source_ref("R12", "Operator entry point and claim boundary", "evals/README.md", "## Claim boundary"),
        source_ref("R13", "Generated report owner and drift renderer", "tools/render-replay-lab-report.py", "def render"),
        source_ref("R14", "Repository-local replay operator skill", "evals/skills/recon-replay-lab/SKILL.md", "## Route from retained state"),
        source_ref("R15", "Copy-ready LLM handoff contracts", "evals/skills/recon-replay-lab/references/handoffs.md", "## Start: operator to fresh replay context"),
        source_ref("R16", "Result interpretation and action mapping", "evals/skills/recon-replay-lab/references/interpretation.md", "## Map outcome to next action"),
        source_ref("R17", "Receipt-derived state and retained evaluation", "tools/replay-ticket.py", "def derive_run_state"),
    ]

    decision_cards = []
    for index, decision in enumerate(decisions, 1):
        groups = " · ".join(" / ".join(group) for group in decision["signals"])
        decision_cards.append(
            '<article class="card flat decision">'
            f'<span class="number">{index}</span>'
            f'<h3>{h(decision["label"])}</h3>'
            f'<p class="muted"><code>{h(decision["id"])}</code></p>'
            f'<p class="muted">Signal groups: {h(groups)}</p>'
            '</article>'
        )

    reference_rows = []
    for ref in refs:
        href = "../" + ref.path
        reference_rows.append(
            f'<li id="ref-{h(ref.ref_id.lower())}">'
            f'<span class="ref-id">{h(ref.ref_id)}</span>'
            f'<span><a href="{h(href)}">{h(ref.title)}</a><br>'
            f'<code>{h(ref.path)}:{ref.line}</code></span>'
            f'<span class="hash" title="{h(ref.digest)}">sha256 {h(ref.digest[:12])}…</span>'
            '</li>'
        )

    repository_tree = f"""recon-plugin/
├── evals/
│   ├── README.md                         operator entry + case ledger
│   ├── CLAUDE.md                         ownership rules
│   ├── skills/recon-replay-lab/           LLM routing + handoffs
│   └── cases/{manifest['id']}/
│       ├── case.json                     cutoff, hashes, commit
│       ├── input/
│       │   └── ticket.json               agent-visible frozen Jira input
│       ├── oracle/
│       │   └── decisions.json            scorer-only expected decisions
│       └── fixtures/
│           ├── atomic-pass.yaml           {total}/{total} clean control
│           └── combined-layout-fail.yaml  atomicity rejection control
├── tools/
│   ├── replay-ticket.py                  validate / prepare / state / evaluate / score
│   ├── test-replay-lab.sh                isolated controls
│   └── render-replay-lab-report.py        this report's owner
└── docs/
    └── replay-lab-report.html             generated view; never hand-edit"""

    prepared_tree = f"""<new replay directory>/
├── REPLAY.md                              exact agent instructions
├── receipt.json                           ticket, repo, and skill fingerprints
├── skill/
│   └── recon-triage/SKILL.md              frozen judgment contract
├── verifier/
│   ├── verify-submission.py                executable oracle-free verifier
│   ├── triage-tools.py                     copied production parser/verifier
│   └── replay-owner-identities.json        explicit replay-only owner tokens
├── target-repo/                           git archive of {target_commit[:12]}…
├── workspace/{ticket_key}/triage/
│   └── ticket.json                        sanitized input copied from case
├── submission/
│   └── triage.yaml                        only replay-agent-authored result
└── evaluation/                            created once by evaluate
    ├── score.txt                          human-readable retained trace
    └── result.json                        machine result + integrity hashes

INTENTIONALLY ABSENT
├── oracle/                                expected answer stays outside
└── fixtures/                              control answers stay outside"""

    setup_command = f"""RECON_PLUGIN="/absolute/path/to/recon-plugin"
cd "$RECON_PLUGIN"

ATT_CASE="{case_rel}"
ATT_TARGET="/absolute/path/to/{manifest['repository']['name']}"
ATT_PARENT="$(mktemp -d /tmp/att-4845-baseline.XXXXXX)"
ATT_RUN="$ATT_PARENT/run"

python3 tools/replay-ticket.py validate "$ATT_CASE"
python3 tools/replay-ticket.py prepare "$ATT_CASE" \\
  --repo "$ATT_TARGET" --out "$ATT_RUN"
python3 tools/replay-ticket.py state "$ATT_RUN""".strip()

    handoffs_text = (ROOT / "evals/skills/recon-replay-lab/references/handoffs.md").read_text(
        encoding="utf-8"
    )
    agent_prompt = extract_between(
        handoffs_text, "--- fresh-context prompt ---", "--- end prompt ---"
    ).replace("<absolute-run-dir>", "$ATT_RUN")

    score_command = """cd "$RECON_PLUGIN"
python3 tools/replay-ticket.py state "$ATT_RUN"
python3 tools/replay-ticket.py evaluate "$ATT_RUN"
python3 tools/replay-ticket.py state "$ATT_RUN""".strip()

    repeat_command = """# Use a new output directory for every run; prepare refuses overwrite.
# Run baseline three times, then the proposed revision three times.
# Retain each receipt.json, submission/triage.yaml, evaluation/score.txt,
# and evaluation/result.json."""

    report = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta name="color-scheme" content="dark light">
  <title>Recon Real-Ticket Replay Laboratory — Operator Report</title>
  <style>{STYLE}</style>
</head>
<body>
<!-- GENERATED by tools/render-replay-lab-report.py. DO NOT EDIT BY HAND. -->
<div class="shell">
  <aside class="sidebar">
    <div class="brand"><div class="mark">R</div><div><strong>Replay Lab</strong><span>Operator report</span></div></div>
    <nav aria-label="Report sections">
      <a href="#thesis">Intent</a>
      <a href="#structure">Folder structure</a>
      <a href="#flow">Execution flow</a>
      <a href="#handoffs">LLM handoffs</a>
      <a href="#ticket">ATT-4845</a>
      <a href="#comparison">Before / after</a>
      <a href="#runbook">Action steps</a>
      <a href="#scoring">Scoring logic</a>
      <a href="#integrity">No-drift controls</a>
      <a href="#scenarios">Scenarios</a>
      <a href="#boundaries">Boundaries</a>
      <a href="#references">References</a>
    </nav>
    <div class="sidebar-note">Generated from live repository sources.<br>Case schema v{manifest['schema_version']} · Oracle schema v{oracle['schema_version']}</div>
  </aside>

  <main>
    <header class="hero" id="thesis">
      <div class="eyebrow">Recon quality · evidence before prompt edits</div>
      <h1>Measure the ticket twice. Change the skill once.</h1>
      <p class="lede">The laboratory freezes a real Jira task and its codebase, hides the expected decisions from the agent, and scores the retained triage. Its intention is not to make ATT-4845 look solved. Its intention is to make a future skill-quality claim falsifiable.</p>
      <div class="hero-grid">
        <div class="card">
          <h3>The observed gap</h3>
          <p>The immutable baseline marked the frozen ticket READY with no decision audit. Calibration retained only decisions whose observable outcome remains externally unselected. {ref_badge('R11')}</p>
          <div><span class="tag good">Clean fixture: {total}/{total}</span><span class="tag bad">Merged audit: rejected</span><span class="tag warn">{len(calibration)} reviewed families</span></div>
        </div>
        <div class="card">
          <div class="metric">{total} decisions</div>
          <p class="muted">Approved blocking decisions from one frozen ambiguous capability-change ticket.</p>
          <div class="metric blue">2 controls</div>
          <p class="muted">One atomic pass, one combined-layout failure.</p>
        </div>
      </div>
      <div class="callout warn" style="margin-top:18px"><strong>Critical distinction:</strong> the lab is an evaluation instrument. Fixtures prove rail mechanics and the calibration bounds the score target. Neither proves a model or plugin revision produces a better fresh-context artifact.</div>
      <div class="callout" style="margin-top:18px"><strong>LLM operating model:</strong> one context prepares and explains, a fresh context generates and stops, then any operator context resumes from the run path. No handoff depends on remembering this report or the prior chat.</div>
    </header>

    <section id="structure">
      <div class="section-head"><div><div class="eyebrow">01 · Ownership</div><h2>Two folder trees, two different jobs</h2></div><p>The repository tree stores benchmark sources and the hidden oracle. The prepared-run tree is the clean room shown to one fresh agent. Mixing these trees would leak the answer.</p></div>
      <div class="two">
        <article class="card"><h3>Repository: maintain the laboratory</h3><pre class="tree">{h(repository_tree)}</pre><p class="legend">Humans maintaining the benchmark may read every branch. {ref_badge('R1')}{ref_badge('R3')}{ref_badge('R8')}</p></article>
        <article class="card"><h3>Prepared run: execute one replay</h3><pre class="tree">{h(prepared_tree)}</pre><p class="legend">The replaying agent gets frozen input and skill bytes—not the rubric or test answers. {ref_badge('R5')}</p></article>
      </div>
      <div class="card" style="margin-top:18px">
        <table class="ownership">
          <thead><tr><th>Location</th><th>Owner</th><th>Why it exists</th><th>Agent visibility</th></tr></thead>
          <tbody>
            <tr><td><code>case.json</code></td><td>Case maintainer</td><td>Pins cutoff, ticket hash and repository commit.</td><td>Copied facts only through the receipt.</td></tr>
            <tr><td><code>input/</code></td><td>Case maintainer</td><td>Contains sanitized task material available at the frozen start state.</td><td><span class="good">Visible</span></td></tr>
            <tr><td><code>oracle/</code></td><td>Independent evaluator</td><td>Defines expected disposition and decision families.</td><td><span class="bad">Excluded</span></td></tr>
            <tr><td><code>fixtures/</code></td><td>Scorer tests</td><td>Proves {total}/{total} passes and a merged audit is rejected.</td><td><span class="bad">Excluded</span></td></tr>
            <tr><td><code>evals/skills/</code></td><td>Repository operator</td><td>Routes LLM start/resume behavior and owns explanatory handoff shapes.</td><td><span class="warn">Operator only</span></td></tr>
            <tr><td><code>target-repo/</code></td><td><code>prepare</code> rail</td><td>Exports exact historical code without current worktree drift.</td><td><span class="good">Visible</span></td></tr>
            <tr><td><code>submission/</code></td><td>Fresh replay agent</td><td>Holds the only generative output being evaluated.</td><td><span class="good">Writable</span></td></tr>
            <tr><td><code>evaluation/</code></td><td><code>evaluate</code> rail</td><td>Persists the human trace and machine result once; hashes connect them to the submission.</td><td><span class="warn">Operator after return</span></td></tr>
          </tbody>
        </table>
      </div>
    </section>

    <section id="flow">
      <div class="section-head"><div><div class="eyebrow">02 · Execution</div><h2>One run path, two LLM contexts</h2></div><p>State and mutation stay on rails. The operator explains and hands off; only the clean replay context performs semantic triage.</p></div>
      <div class="flow">
        <div class="step"><b>1 · Prepare</b><span>Operator validates, freezes exact inputs, excludes the oracle, then derives PREPARED.</span></div>
        <div class="step"><b>2 · Explain</b><span>Operator reports what is frozen, excluded, writable, and forbidden.</span></div>
        <div class="step"><b>3 · Hand off + stop</b><span>Copy-ready prompt sends only the run path to a genuinely fresh context.</span></div>
        <div class="step"><b>4 · Generate + verify + return</b><span>Replay LLM writes submission/triage.yaml, runs the bundled verifier clean, returns the run path, and stops.</span></div>
        <div class="step"><b>5 · Derive + evaluate</b><span>Operator derives SUBMITTED; evaluate verifies, scores, and retains two artifacts once.</span></div>
        <div class="step"><b>6 · Explain + act</b><span>SCORED output names result, evidence boundary, artifact paths, and exact next action.</span></div>
      </div>
      <div class="callout" style="margin-top:20px"><strong>Why this order:</strong> the operator context can prepare and later interpret an oracle-backed score, but it is contaminated for generation. The fresh context can generate, but cannot evaluate itself. The run directory reconnects them without sharing chat history. {ref_badge('R14')}{ref_badge('R15')}{ref_badge('R17')}</div>
    </section>

    <section id="handoffs">
      <div class="section-head"><div><div class="eyebrow">03 · LLM handoff</div><h2>A follow-up another LLM can actually execute</h2></div><p>A good handoff answers four questions: what happened, where is the evidence, what happens next, and when must this context stop.</p></div>
      <div class="two">
        <article class="card"><h3>Before: chat history was hidden state</h3><p class="muted">The operator had to remember the case path, whether generation finished, which score command to run, and where terminal output went. A new LLM received a narrative and reconstructed progress.</p><div class="callout bad"><strong>Failure mode:</strong> the operator context could accidentally author the submission, the returning context could omit the case, or scoring could be rerun and lose the original trace.</div></article>
        <article class="card"><h3>After: the run directory is the handle</h3><p class="muted"><code>state &lt;run&gt;</code> derives PREPARED, SUBMITTED, or SCORED from validated files. It prints the exact next command. <code>evaluate</code> writes the human trace and machine result once.</p><div class="callout"><strong>Handoff:</strong> pass one absolute run path. Any project LLM can resume without reading the prior conversation. {ref_badge('R14')}{ref_badge('R17')}</div></article>
      </div>
      <div class="card" style="margin-top:18px">
        <div class="compare-head"><div><h3>Copy into a fresh replay conversation</h3><span class="tag warn">operator stops after copy</span></div><button class="copy" data-copy="fresh-context-prompt">Copy</button></div>
        <pre class="terminal" id="fresh-context-prompt" style="min-height:auto">{h(agent_prompt)}</pre>
        <p class="muted" style="margin-top:12px">This prompt is extracted from the handoff reference during report generation, so the report cannot silently drift from the skill. {ref_badge('R15')}</p>
      </div>
      <div class="compare" style="margin-top:18px">
        <article class="card"><div class="compare-head"><h3>1 · Prepared</h3><span class="tag">live rail output</span></div><pre class="terminal" style="min-height:auto">{h(prepared_output)}</pre></article>
        <article class="card"><div class="compare-head"><h3>2 · Submitted</h3><span class="tag">live rail output</span></div><pre class="terminal" style="min-height:auto">{h(submitted_output)}</pre></article>
        <article class="card"><div class="compare-head"><h3>3 · Evaluate once</h3><span class="tag good">exit {evaluate_status}</span></div><pre class="terminal" style="min-height:auto">{h(evaluated_output)}</pre></article>
        <article class="card"><div class="compare-head"><h3>4 · Scored</h3><span class="tag good">persisted</span></div><pre class="terminal" style="min-height:auto">{h(scored_output)}</pre></article>
      </div>
      <div class="callout warn" style="margin-top:18px"><strong>What this live control proves:</strong> the same ATT-4845 fixture passes the bundled offline verifier, moves through all file states, and retains a {total}/{total} result with no conversational state. It is an E2 workflow-mechanics result, not a fresh-model quality result.</div>
    </section>

    <section id="ticket">
      <div class="section-head"><div><div class="eyebrow">04 · Real origin</div><h2>{h(ticket_key)} at the pre-comment cutoff</h2></div><p>{h(ticket['fields']['summary'])}. Snapshot {h(manifest['source']['snapshot_at'])}; {h(manifest['source']['human_comments'])} human comments; target <code>{h(target_commit)}</code>. {ref_badge('R1')}{ref_badge('R2')}</p></div>
      <div class="callout"><strong>Why pre-comment:</strong> the later human analysis enumerated the answers. Including it would leak the benchmark. The agent must recover decision boundaries from the original ticket and frozen source.</div>
      <div class="two" style="margin-top:18px">{''.join(decision_cards)}</div>
    </section>

    <section id="comparison">
      <div class="section-head"><div><div class="eyebrow">05 · Concrete control</div><h2>Same production validity, different decision quality</h2></div><p>These are scorer controls, not claims about a fresh model run. Their purpose is to prove that the lab distinguishes the exact failure we observed.</p></div>
      <div class="compare">
        <article class="card">
          <div class="compare-head"><div><h3>Combined blocker</h3><span class="tag bad">exit {combined_status}</span></div><button class="copy" data-copy="combined-output">Copy</button></div>
          <p class="muted">Six blockers. Keyword presentation and intro layout share blocker 2.</p>
          <pre class="terminal" id="combined-output">{h(combined_output)}</pre>
        </article>
        <article class="card">
          <div class="compare-head"><div><h3>Atomic blockers</h3><span class="tag good">exit {atomic_status}</span></div><button class="copy" data-copy="atomic-output">Copy</button></div>
          <p class="muted">{total} blockers. Each independently approved decision can be answered separately.</p>
          <pre class="terminal" id="atomic-output">{h(atomic_output)}</pre>
        </article>
      </div>
      <div class="three" style="margin-top:18px">
        <div class="card flat"><div class="metric good">PASS</div><p>Both candidates pass the real production artifact verifier.</p></div>
        <div class="card flat"><div class="metric bad">REJECTED</div><p>The combined candidate violates the audit-to-blocker bijection.</p></div>
        <div class="card flat"><div class="metric blue">{total}/{total}</div><p>The atomic candidate covers every approved decision distinctly.</p></div>
      </div>
    </section>

    <section id="runbook">
      <div class="section-head"><div><div class="eyebrow">06 · Operator runbook</div><h2>Run and resume without hidden context</h2></div><p>Use the local skill when an LLM operates the lab. Every attempt receives a new directory and a fresh generation context; the run path survives every handoff.</p></div>
      <div class="runbook">
        <article class="runstep"><h3>Verify the laboratory before trusting it</h3><p>Set <code>RECON_PLUGIN</code> to this repository clone. The suite tests clean and failing scoring, all three states, retained evaluation, tampering, oracle isolation, exact commit export, symlinks, inconsistent files, and overwrite refusal.</p>{command_block('cmd-test', 'RECON_PLUGIN="/absolute/path/to/recon-plugin"\ncd "$RECON_PLUGIN"\nbash tools/test-replay-lab.sh')}</article>
        <article class="runstep"><h3>Validate, prepare, and derive PREPARED</h3><p>Replace <code>ATT_TARGET</code> once with the local target repository. The output directory must not exist. The final command tells you what the next context must do.</p>{command_block('cmd-prepare', setup_command)}<details><summary>Observed validation evidence</summary><pre class="terminal" style="min-height:auto">exit {validate_status}\n{h(validate_output)}</pre></details></article>
        <article class="runstep"><h3>Hand off to a genuinely fresh agent context</h3><p>Set its working directory to <code>$ATT_RUN</code>. Paste the prompt. The operator context stops; the fresh context writes one file, copies only listed replay-only owner tokens, verifies it clean, and returns the run path.</p>{command_block('cmd-agent', agent_prompt)}</article>
        <article class="runstep"><h3>Resume, evaluate once, and retain the outcome</h3><p>First derive state. Only SUBMITTED may evaluate. Exit 1 is a retained quality result; a failed bundled verifier is exit 2 and creates no coverage evidence. The final state must be SCORED.</p>{command_block('cmd-score', score_command)}</article>
        <article class="runstep"><h3>Repeat before and after</h3><p>Three baseline runs and three proposed-revision runs expose variance. Do not repair a submission silently; record intervention as an outcome.</p>{command_block('cmd-repeat', repeat_command)}</article>
      </div>
    </section>

    <section id="scoring">
      <div class="section-head"><div><div class="eyebrow">07 · Scoring</div><h2>Why one blocker cannot earn two decisions</h2></div><p>Signal matching creates candidate edges. Maximum bipartite matching then assigns each decision to at most one blocker and each blocker to at most one decision. {ref_badge('R3')}{ref_badge('R6')}</p></div>
      <div class="card">
        <div class="matching">
          <div><div class="node">Open decision A</div><div class="node">Open decision B</div></div>
          <div class="edges">↘<br>↗</div>
          <div><div class="node bad">One blocker</div></div>
        </div>
        <div class="callout bad" style="margin-top:16px"><strong>Result:</strong> the production verifier rejects the candidate before scoring because one blocker cannot map to two independently answerable OPEN decisions.</div>
      </div>
      <div class="callout warn" style="margin-top:18px"><strong>Known limitation:</strong> the case oracle remains lexical and case-specific. A valid unseen synonym may false-fail; an agent with oracle access could keyword-stuff. The closure rail prevents structural ambiguity, not semantic overfitting. Independent review remains required.</div>
    </section>

    <section id="integrity">
      <div class="section-head"><div><div class="eyebrow">08 · Integrity</div><h2>No-drift controls and their failure behavior</h2></div><p>“No drift” means important duplication has an owner and a mechanical disagreement check. It does not mean the benchmark can never require a reviewed update.</p></div>
      <div class="integrity">
        <div class="card flat"><b>Ticket SHA-256</b><span class="muted">Changing one byte in input/ticket.json makes <code>validate</code> exit 2 with <code>input hash drift</code>.</span></div>
        <div class="card flat"><b>Target commit</b><span class="muted"><code>prepare</code> verifies the full object ID and archives those exact source bytes.</span></div>
        <div class="card flat"><b>Skill fingerprint</b><span class="muted">receipt.json records the copied SKILL.md hash and source commit/dirty state.</span></div>
        <div class="card flat"><b>Bundled verifier fingerprint</b><span class="muted">receipt.json hashes the copied production parser, executable wrapper, and replay-only owner map; drift exits 2.</span></div>
        <div class="card flat"><b>Oracle separation</b><span class="muted">Only input, skill and target source enter the run; tests scan for secret oracle tokens.</span></div>
        <div class="card flat"><b>State consistency</b><span class="muted">Receipt mismatch, symlinks, partial evaluation, and candidate or score hash drift exit 2 instead of guessing.</span></div>
        <div class="card flat"><b>No overwrite</b><span class="muted">Existing run and evaluation directories are rejected, preserving prior evidence.</span></div>
        <div class="card flat"><b>Atomic retention</b><span class="muted"><code>evaluate</code> publishes score.txt and result.json together and rolls back a caught partial write.</span></div>
        <div class="card flat"><b>Report byte check</b><span class="muted">The generator re-runs controls, resolves line references/hashes, and compares exact HTML bytes in coherence.</span></div>
      </div>
      <div class="card" style="margin-top:18px"><h3>Source-derived report contract</h3><p>This HTML is never hand-edited. <code>python3 tools/render-replay-lab-report.py --check</code> rebuilds it in memory. A changed source, command diagnostic, reference line, or generator template produces different bytes and fails repository coherence. {ref_badge('R10')}{ref_badge('R13')}</p></div>
    </section>

    <section id="scenarios">
      <div class="section-head"><div><div class="eyebrow">09 · Concrete scenarios</div><h2>What different outcomes mean</h2></div><p>The lab separates handoff, mechanism, and generative-quality failures so the next action is specific.</p></div>
      <div class="card">
        <div class="scenario"><strong>Scenario A — the user returns only a run path.</strong><br><span class="muted">Run <code>state &lt;run&gt;</code>. The receipt derives the case; SUBMITTED prints the exact evaluate command. Prior chat is unnecessary.</span></div>
        <div class="scenario"><strong>Scenario B — the fresh LLM has not written a submission.</strong><br><span class="muted">State remains PREPARED. Reissue the clean-context handoff and stop; the operator must not fill the missing YAML.</span></div>
        <div class="scenario"><strong>Scenario C — candidate fails its bundled verifier.</strong><br><span class="muted"><code>evaluate</code> exits 2 without retaining a score or decision coverage. Return the fresh context to the exact verifier command; do not call this a quality result.</span></div>
        <div class="scenario"><strong>Scenario D — disposition is wrong.</strong><br><span class="muted">Artifact is valid, but expected BLOCKED differs. Investigate the six triage checks before blocker wording.</span></div>
        <div class="scenario"><strong>Scenario E — merged OPEN decisions.</strong><br><span class="muted">The artifact verifier rejects the candidate. Split the independently answerable decisions before it can enter scoring.</span></div>
        <div class="scenario"><strong>Scenario F — full coverage in one run only.</strong><br><span class="muted">Promising but not stable. Repeat in fresh contexts; do not call the shipped skill improved from one sample.</span></div>
        <div class="scenario"><strong>Scenario G — evaluation is already SCORED.</strong><br><span class="muted">Read the retained JSON and trace. Never rerun or revise evaluation; start another run for another sample.</span></div>
        <div class="scenario"><strong>Scenario H — synonym judged valid by a reviewer.</strong><br><span class="muted">Amend the oracle through review, rerender this report, and retain why the rubric changed. Do not hand-edit a score.</span></div>
      </div>
    </section>

    <section id="boundaries">
      <div class="section-head"><div><div class="eyebrow">10 · Decision record</div><h2>What I chose—and what I refused to claim</h2></div><p>The architecture follows the repository’s outcome-first behavior contract rather than optimizing for a persuasive demo.</p></div>
      <div class="two">
        <article class="card"><h3>Decisions and reasoning</h3><ul>
          <li><strong>Instrument before skill edit:</strong> otherwise baseline and fix are designed together.</li>
          <li><strong>Real ticket, pre-comment:</strong> observed origin without answer leakage.</li>
          <li><strong>Full target commit:</strong> code evidence remains inspectable while the current dirty branch is irrelevant.</li>
          <li><strong>Production verifier first:</strong> quality scores never legitimize invalid Recon output.</li>
          <li><strong>Replay-only owner map:</strong> offline preparation supplies explicit non-Jira tokens instead of guessing an account ID.</li>
          <li><strong>One-to-one matching:</strong> decision atomicity becomes a mechanical property.</li>
          <li><strong>Repository-local operator skill:</strong> LLMs receive the same routing and handoff contract without shipping internal oracles in the plugin.</li>
          <li><strong>Run path as single handle:</strong> receipt-derived state replaces conversation memory and evaluation preserves its own integrity links.</li>
          <li><strong>Generated HTML:</strong> explanation is a checked view, not a drifting parallel specification.</li>
        </ul></article>
        <article class="card boundary"><h3>Explicit non-claims</h3><ul>
          <li>No fresh-context model baseline has yet been recorded.</li>
          <li>No shipped Recon SKILL.md generative behavior was changed or proven better in this milestone.</li>
          <li>Fixtures prove scorer properties, not generative quality.</li>
          <li>The local operator skill validates structurally, but activation quality is not yet forward-tested across model tiers.</li>
          <li>The offline verifier does not test activation, live Jira transport, visual repro, or delivery.</li>
          <li>One ambiguous BLOCKED ticket does not establish “works for any task.”</li>
          <li>Filesystem isolation is procedural; a fully unrestricted agent could inspect the source repository.</li>
        </ul></article>
      </div>
      <div class="callout" style="margin-top:18px"><strong>Next accountable move:</strong> use the new handoff to run the current clean plugin revision three times from this prepared state, retain every submission and evaluation, then revise the shipped triage skill only if the failure reproduces. Add READY and NEEDS_INFO cases before a general quality claim. {ref_badge('R9')}{ref_badge('R12')}{ref_badge('R16')}</div>
    </section>

    <section id="references">
      <div class="section-head"><div><div class="eyebrow">11 · Evidence ledger</div><h2>Current source references</h2></div><p>Line numbers and SHA-256 prefixes are computed during generation. The relative links open the owning repository file; the hash exposes content drift.</p></div>
      <div class="card"><ol class="refs">{''.join(reference_rows)}</ol></div>
    </section>

    <footer>
      Generated deterministically by <code>tools/render-replay-lab-report.py</code> from {len(refs)} referenced sources. Ticket input SHA-256 <code>{h(manifest['input']['sha256'])}</code>. No network resources.
    </footer>
  </main>
</div>
<script>{SCRIPT}</script>
</body>
</html>
"""
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if the checked-in report differs")
    args = parser.parse_args(argv)
    expected = render()
    if args.check:
        if not OUTPUT.is_file():
            print(f"replay report: missing — {OUTPUT.relative_to(ROOT)}", file=sys.stderr)
            return 1
        actual = OUTPUT.read_text(encoding="utf-8")
        if actual != expected:
            print(
                "replay report: DRIFT — run python3 tools/render-replay-lab-report.py",
                file=sys.stderr,
            )
            return 1
        print(
            "replay report: clean — source hashes, references, commands, and HTML agree"
        )
        return 0
    OUTPUT.write_text(expected, encoding="utf-8")
    print(f"replay report: wrote {OUTPUT.relative_to(ROOT)} ({len(expected.encode('utf-8'))} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
