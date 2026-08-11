#!/usr/bin/env python3
"""Render the source-linked overview of Recon's four operating flows."""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import re
import subprocess
import sys
import tomllib
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "docs" / "system-map.html"
ITERATION = ROOT / "docs" / "improvement-proposals" / "0.22.0" / "requirement-closure-coverage"

VERSION_STAMP = re.compile(r"\d+\.\d+\.\d+")


def bump_stamped_markers() -> dict[str, tuple[str, ...]]:
    """Line markers `cz bump` rewrites, read from .cz.toml — its only owner.

    A reference hash must not move just because a release renumbered a stamp.
    The bump is a real commit, so its pre-commit hook runs check-coherence.sh
    BEFORE this map could be regenerated, and a whole-file hash of a
    bump-rewritten file makes every release refuse itself. Deriving the markers
    from version_files means adding a file there cannot reintroduce that.
    """
    config = tomllib.loads((ROOT / ".cz.toml").read_text(encoding="utf-8"))
    markers: dict[str, tuple[str, ...]] = {}
    for entry in config["tool"]["commitizen"]["version_files"]:
        relative, _, marker = entry.partition(":")
        if marker:
            markers[relative] = markers.get(relative, ()) + (marker,)
    return markers


def digest(path: Path, relative: str | None = None) -> str:
    markers = bump_stamped_markers().get(relative or "")
    if not markers:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    # keepends: separator identity is part of the file, so a stripped trailing
    # newline or a CRLF conversion still counts as drift.
    normalized = "".join(
        VERSION_STAMP.sub("<version>", text) if any(marker in text for marker in markers) else text
        for text in path.read_text(encoding="utf-8").splitlines(keepends=True)
    )
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()


def ref(ref_id: str, title: str, relative: str, needle: str) -> dict:
    path = ROOT / relative
    for line, text in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if needle in text:
            return {"id": ref_id, "title": title, "path": relative, "line": line, "hash": digest(path, relative)}
    raise RuntimeError(f"reference needle not found: {relative}: {needle}")


def source_state() -> dict:
    result = subprocess.run(
        [sys.executable, "tools/improvement-cycle.py", "state", str(ITERATION.relative_to(ROOT)), "--json"],
        cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "improvement state failed")
    return json.loads(result.stdout)


def esc(value: object) -> str:
    return html.escape(str(value), quote=True)


def reference_link(item: dict) -> str:
    return f'<a href="../{esc(item["path"])}" title="line {item["line"]}">{esc(item["id"])}</a>'


def render() -> str:
    iteration = yaml.safe_load((ITERATION / "iteration.yaml").read_text(encoding="utf-8"))
    target_ticket = json.loads((ROOT / "evals/cases/att-4845-pre-comment/input/ticket.json").read_text(encoding="utf-8"))
    control_ticket = json.loads((ROOT / "evals/cases/requirement-closure-ready-control/input/ticket.json").read_text(encoding="utf-8"))
    state = source_state()
    refs = [
        ref("R1", "Runtime state machine", "recon/docs/pipeline.md", "## State machine"),
        ref("R2", "Runtime artifact registry", "recon/docs/registry.yaml", 'pattern: "triage/triage.yaml"'),
        ref("R3", "Runtime visual flow", "docs/flow.html", "<title>Recon Pipeline"),
        ref("R4", "Laboratory operator contract", "evals/README.md", "## LLM workflow"),
        ref("R5", "Laboratory state routing", "evals/skills/recon-replay-lab/SKILL.md", "## Route from retained state"),
        ref("R6", "Improvement state routing", "evals/skills/recon-improvement-loop/SKILL.md", "## Route from retained state"),
        ref("R7", "Current experiment contract", "docs/improvement-proposals/0.22.0/requirement-closure-coverage/iteration.yaml", "improvement_id:"),
        ref("R8", "Candidate implementation boundary", "docs/improvement-proposals/0.22.0/requirement-closure-coverage/candidate-implementation-brief.md", "## Scope"),
        ref("R9", "ATT-4845 frozen public input", "evals/cases/att-4845-pre-comment/input/ticket.json", '"summary"'),
        ref("R10", "READY-control public input", "evals/cases/requirement-closure-ready-control/input/ticket.json", '"summary"'),
        ref("R11", "Version-review structure contract", "evals/version-reviews/README.md", "## External folder model"),
        ref("R12", "Version-review schema", "evals/version-reviews/schema.yaml", "capture_paths:"),
        ref("R13", "Version-review operator workflow", "evals/skills/recon-version-review/SKILL.md", "## Workflow"),
        ref("R14", "Version-review mutation rail", "tools/version-review.py", "def command_init"),
    ]
    ref_rows = "".join(
        f'<tr id="ref-{item["id"].lower()}"><td>{reference_link(item)}</td><td>{esc(item["title"])}</td><td><code>{esc(item["path"])}:{item["line"]}</code></td><td><code>{esc(item["hash"][:12])}…</code></td></tr>'
        for item in refs
    )
    current = state["next_action"]
    return f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Recon System Map</title>
<style>
:root{{color-scheme:light dark;--bg:light-dark(#f7f7f4,#10131a);--panel:light-dark(#fff,#181d27);--text:light-dark(#17202a,#edf2fa);--muted:light-dark(#536274,#b8c4d3);--line:light-dark(#d9e0e8,#344052);--runtime:light-dark(#176b53,#72d6af);--lab:light-dark(#17629b,#79c4ff);--loop:light-dark(#7a4c10,#f2bd6b)}}*{{box-sizing:border-box}}body{{margin:0;background:var(--bg);color:var(--text);font:16px/1.5 system-ui,sans-serif}}main{{max-width:1120px;margin:auto;padding:42px 24px 80px}}h1{{font-size:clamp(2rem,5vw,4rem);line-height:1;margin:0 0 12px}}h2{{margin:0 0 10px}}p{{margin:0 0 12px}}.lede{{max-width:75ch;color:var(--muted);font-size:1.08rem}}.now,.card,.step{{background:var(--panel);border:1px solid var(--line);border-radius:14px}}.now{{margin:28px 0;padding:18px;border-left:5px solid var(--loop)}}.lanes{{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:15px}}.grid{{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:15px}}.card{{padding:18px}}.runtime{{border-top:5px solid var(--runtime)}}.lab{{border-top:5px solid var(--lab)}}.loop{{border-top:5px solid var(--loop)}}.flow{{display:grid;gap:10px;margin-top:18px}}.step{{padding:14px}}.step b{{display:block;margin-bottom:5px}}.io{{display:grid;grid-template-columns:90px 1fr;gap:4px 12px;font-size:.93rem}}.io strong{{color:var(--muted)}}section{{margin-top:48px}}table{{width:100%;border-collapse:collapse;font-size:.9rem}}th,td{{padding:10px;border-bottom:1px solid var(--line);text-align:left;vertical-align:top}}th{{color:var(--muted)}}code{{font-size:.88em}}a{{color:inherit;text-underline-offset:3px}}.arrow{{text-align:center;color:var(--muted);font-size:1.3rem}}.state{{font-size:1.15rem;font-weight:700}}@media(max-width:900px){{.lanes{{grid-template-columns:repeat(2,minmax(0,1fr))}}}}@media(max-width:760px){{main{{padding:28px 16px 56px}}.lanes,.grid{{grid-template-columns:1fr}}}}@media print{{body{{background:#fff;color:#111}}.now,.card,.step{{box-shadow:none}}}}
</style></head><body><main>
<p>Generated system map · source-linked and drift-checked</p><h1>Recon has four separate flows.</h1>
<p class="lede">The shipped plugin handles a real Jira ticket. Private version review collects teammate feedback. The replay laboratory tests one frozen skill snapshot. The improvement loop decides how we change that skill. They connect, but they must not be confused.</p>
<div class="now"><div class="state">Now: {esc(state["state"])} · attempt {esc(state["attempt"])}</div><p>Retained: baseline={state["counts"]["baseline"]}, candidate={state["counts"]["candidate"]}, negative-control={state["counts"]["negative-control"]}.</p><p><strong>Next:</strong> {esc(current)}</p></div>
<section><h2>System map</h2><div class="lanes"><article class="card runtime"><h3>1 · Shipped plugin</h3><p>Real ticket → evidence-backed decision → human-gated output.</p><p><a href="#runtime">See inputs and outputs</a></p></article><article class="card lab"><h3>2 · Private version review</h3><p>Many dossiers → teammate findings → version-level themes.</p><p><a href="#version-review">See the external tree</a></p></article><article class="card lab"><h3>3 · Replay laboratory</h3><p>Frozen case → fresh LLM submission → immutable score.</p><p><a href="#laboratory">See states</a></p></article><article class="card loop"><h3>4 · Improvement loop</h3><p>Baseline evidence → candidate → comparison → review.</p><p><a href="#improvement">See current attempt</a></p></article></div><p class="arrow">private feedback → sanitized proposal → replay and negative control → retained evidence → reviewed improvement decision</p></section>
<section id="runtime"><h2>1 · Main plugin: real Jira work</h2><p>Input: a Jira ticket and a read-only target repository. Output: either a precise blocker package or an approved implementation handoff. Recon never edits product code. {reference_link(refs[0])} {reference_link(refs[1])} {reference_link(refs[2])}</p><div class="flow"><div class="step"><b>Fresh workspace + triage</b><div class="io"><strong>Input</strong><span>Ticket ID/URL, Jira facts, repository evidence.</span><strong>Output</strong><span><code>triage/ticket.json</code> and verified <code>triage/triage.yaml</code>.</span><strong>ATT-4845</strong><span>Current baseline says BLOCKED, but only asks about fallback threshold and order.</span></div></div><div class="step"><b>BLOCKED / NEEDS_INFO path</b><div class="io"><strong>Input</strong><span>One or more atomic blockers.</span><strong>Output</strong><span>Dossier, rendered comment, attachments and an explicit posting gate.</span><strong>Stop</strong><span>Owners answer on Jira; start a new triage run after answers arrive.</span></div></div><div class="step"><b>READY path: discovery → route → approval</b><div class="io"><strong>Input</strong><span>Verified READY triage.</span><strong>Output</strong><span><code>discovery/discovery.md</code>, <code>route/routing.yaml</code>, optional repro, brief and approval record.</span><strong>Example</strong><span>RCTRL-1: “Reset filters” has exact visible behavior, so it should proceed without blockers.</span></div></div><div class="step"><b>Final STOP</b><div class="io"><strong>Output</strong><span>Human-approved delivery package and a verbatim implementation handoff.</span><strong>Boundary</strong><span>A new implementation session writes product code; Recon stops.</span></div></div></div></section>
<section id="version-review"><h2>2 · Private version review: learn from many live dossiers</h2><p>The producing plugin version—not sprint membership—owns the review cycle. Live reports and teammate feedback stay in an operator-selected private root; only the generic contract and controls are checked in. {reference_link(refs[10])} {reference_link(refs[11])} {reference_link(refs[12])} {reference_link(refs[13])}</p><div class="flow"><div class="step"><b>COLLECTING</b><p><code>versions/vX.Y.Z/</code> pins the release tag and commit. Each ticket may have multiple immutable run IDs; capture copies only the allowlisted minimal dossier evidence and never Jira results, raw ticket exports, history, or archived runs.</p></div><div class="step"><b>REVIEWING</b><p>Teammates author independent findings against the retained dossier hash, then resolve accepted and disputed findings in one consensus record per run.</p></div><div class="step"><b>SYNTHESIZED → CLOSED</b><p>Cross-ticket findings become themes and explicit <code>PROPOSE</code>, <code>MONITOR</code>, or <code>REJECT</code> decisions. Proposed themes link to a future cohort; they do not change Recon or prove improvement.</p></div></div></section>
<section id="laboratory"><h2>3 · Laboratory: test a skill, not a Jira ticket</h2><p>The laboratory freezes a case and target commit, keeps the scoring oracle away from the fresh LLM, then retains a one-time result. It never contacts Jira. {reference_link(refs[3])} {reference_link(refs[4])}</p><div class="grid"><div class="card lab"><h3>PREPARED</h3><p><strong>Input:</strong> frozen case + skill snapshot + target commit.</p><p><strong>Output:</strong> run directory, <code>REPLAY.md</code>, receipt and verifier; no submission.</p></div><div class="card lab"><h3>SUBMITTED</h3><p><strong>Input:</strong> fresh LLM follows <code>REPLAY.md</code>.</p><p><strong>Output:</strong> verifier-clean <code>submission/triage.yaml</code>.</p></div><div class="card lab"><h3>SCORED</h3><p><strong>Input:</strong> submitted artifact + hidden oracle, operator only.</p><p><strong>Output:</strong> immutable <code>result.json</code> and <code>score.txt</code>.</p></div></div><p><strong>Concrete ATT-4845 baseline:</strong> artifact PASS, disposition BLOCKED, raw decision coverage 1/3; the two stable misses are feature-context mapping and configuration ownership. {reference_link(refs[8])}</p></section>
<section id="improvement"><h2>4 · Improvement loop: change the plugin carefully</h2><p>This is maintainer-only infrastructure. It preserves the laboratory evidence, binds candidate/control runs to one contract, and requires an explicit review before acceptance. {reference_link(refs[5])} {reference_link(refs[6])} {reference_link(refs[7])}</p><div class="flow"><div class="step"><b>Baseline</b><p>Three ATT-4845 SCORED runs are retained. They establish the real failure before we edit the skill.</p></div><div class="step"><b>Candidate — current state</b><p>{state["counts"]["candidate"]} candidate run(s) are retained for attempt {esc(state["attempt"])}. The durable state is {esc(state["state"])}; the linked brief remains the bounded implementation and claim boundary.</p></div><div class="step"><b>Negative control</b><p>{state["counts"]["negative-control"]} same-candidate run(s) are retained against RCTRL-1. Its required outcome remains READY: reset chips, preserve query, rerun search, restore focus. {reference_link(refs[9])}</p></div><div class="step"><b>Compare and review</b><p>The rail retains comparison evidence and an explicit accept, iterate, or reject review. Current next action: {esc(current)}. Even acceptance does not prove all ticket classes.</p></div></div></section>
<section><h2>Reference ledger</h2><p>Every reference below is resolved at generation time. A changed source line or source hash changes this HTML, and <code>--check</code> fails until it is regenerated.</p><table><thead><tr><th>Ref</th><th>Owner</th><th>Source</th><th>SHA-256</th></tr></thead><tbody>{ref_rows}</tbody></table></section>
</main></body></html>'''


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    rendered = render()
    if args.check:
        if not OUTPUT.is_file() or OUTPUT.read_text(encoding="utf-8") != rendered:
            print(f"system map: drift — {OUTPUT.relative_to(ROOT)}", file=sys.stderr)
            return 1
        print("system map: clean — sources, state, references, and HTML agree")
        return 0
    OUTPUT.write_text(rendered, encoding="utf-8")
    print(f"system map: rendered — {OUTPUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
