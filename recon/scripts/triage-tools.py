#!/usr/bin/env python3
# triage-tools.py — shared engine behind verify-triage.sh (invariant 15) and
# render-comment.sh (invariant 13). Not invoked directly; the bash wrappers
# own argument validation and paths.
#
#   python3 triage-tools.py verify <workspace-dir>
#   python3 triage-tools.py render <workspace-dir> <TICKET>
#
# verify — three mechanical passes over triage/triage.yaml:
#   1. schema: required keys, enum values, blocker structure
#   2. disposition: derived from the six checks and compared; a mismatch is a
#      failure in the CHECKS' favor — fix the checks, never hand-edit the verdict
#   3. quotes: every evidence entry is typed; `kind: quote` entries must appear
#      VERBATIM (whitespace/curly-quote normalized) in the named source inside
#      triage/ticket.json — human content only, marker comments are output
# render — emits triage/jira/comment.txt (invariant 13's n+4 shape) from
#   triage.yaml + meta.yaml only. The model never writes the comment.
#
# The YAML dialect is the fixed schema in recon-triage SKILL.md step 3 —
# exact two-space indent steps, double-quoted or bare scalars, block lists.
# Parsed by hand on purpose: no PyYAML dependency, and an indentation drift
# that a lenient parser would forgive is itself a schema violation here.
import json
import re
import sys
from pathlib import Path

MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
          "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
EVIDENCE_KINDS = {"quote", "http", "git", "file", "note"}
SCALAR_ENUMS = {
    "task_class": {"defect", "capability-change", "chore"},
    "disposition": {"READY", "BLOCKED", "NEEDS_INFO"},
    "outcome_decidable": {"true", "partial", "false"},
    "evidence_ok": {"true", "false"},
    "product_decision_open": {"true", "false"},
    "design_dependency": {"true", "false"},
    "backend_dependency": {"true", "false"},
}
REQUIRED_SCALARS = ["recon", "ticket", "title", "task_class", "disposition",
                    "outcome_decidable", "evidence_ok", "product_decision_open",
                    "design_dependency", "backend_dependency"]


def unquote(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == '"' and v[-1] == '"':
        return v[1:-1]
    if len(v) >= 2 and v[0] == "'" and v[-1] == "'":
        return v[1:-1]
    return v


def normalize(s):
    s = s.replace("‘", "'").replace("’", "'")
    s = s.replace("“", '"').replace("”", '"')
    s = s.replace(" ", " ")
    return re.sub(r"\s+", " ", s).strip()


def parse_triage(path, errors):
    """Parse the fixed triage.yaml schema into a dict. Indentation is part of
    the schema (the shape rail counts `^  - title:`), so unexpected indents are
    reported, not forgiven."""
    doc = {"scalars": {}, "blockers": [], "conflicts": 0, "evidence": []}
    lines = path.read_text(encoding="utf-8").splitlines()
    section = None      # None | blockers | conflicts | evidence
    blocker = None
    in_detail = False
    detail_list = None  # None | options | evidence
    ev_entry = None     # current typed evidence entry (top-level or detail)

    def close_entry():
        nonlocal ev_entry
        ev_entry = None

    for ln, raw in enumerate(lines, 1):
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        line = raw.strip()

        if indent == 0:
            close_entry()
            blocker = None
            in_detail = False
            detail_list = None
            key, sep, val = line.partition(":")
            if not sep:
                errors.append(f"yaml:{ln}: unparseable top-level line: {line}")
                continue
            val = val.strip()
            if key in ("blockers", "conflicts", "evidence"):
                section = key
                if val == "[]":
                    section = None
                elif val:
                    errors.append(f"yaml:{ln}: {key} must be a block list or []")
            else:
                section = None
                doc["scalars"][key] = unquote(val)
            continue

        if section == "conflicts":
            if indent == 2 and line.startswith("- "):
                doc["conflicts"] += 1
            continue

        if section == "evidence":
            if indent == 2 and line.startswith("- "):
                close_entry()
                ev_entry = {"_line": ln}
                doc["evidence"].append(ev_entry)
                line = line[2:].strip()
                indent = 4  # fall through to key handling below
            if ev_entry is not None and indent == 4 and ":" in line:
                key, _, val = line.partition(":")
                ev_entry[key.strip()] = unquote(val)
            elif ev_entry is None:
                errors.append(f"yaml:{ln}: evidence entry must start '  - kind: …'")
            continue

        if section == "blockers":
            if indent == 2 and line.startswith("- "):
                close_entry()
                in_detail = False
                detail_list = None
                blocker = {"_line": ln, "detail": {}}
                doc["blockers"].append(blocker)
                key, sep, val = line[2:].partition(":")
                if key.strip() != "title" or not sep:
                    errors.append(f"yaml:{ln}: blocker entries must start '  - title:'")
                else:
                    blocker["title"] = unquote(val)
                continue
            if blocker is None:
                errors.append(f"yaml:{ln}: content before first '  - title:' in blockers")
                continue
            if indent == 4:
                close_entry()
                detail_list = None
                key, sep, val = line.partition(":")
                key = key.strip()
                if key == "detail":
                    in_detail = True
                else:
                    in_detail = False
                    blocker[key] = unquote(val)
                continue
            if in_detail and indent == 6:
                close_entry()
                key, sep, val = line.partition(":")
                key, val = key.strip(), val.strip()
                if key in ("options", "evidence"):
                    detail_list = key
                    blocker["detail"].setdefault(key, [])
                    if val == "[]":
                        detail_list = None
                    elif val:
                        errors.append(f"yaml:{ln}: detail.{key} must be a block list or []")
                else:
                    detail_list = None
                    blocker["detail"][key] = unquote(val)
                continue
            if in_detail and detail_list == "options" and indent == 8 and line.startswith("- "):
                blocker["detail"]["options"].append(unquote(line[2:]))
                continue
            if in_detail and detail_list == "evidence":
                if indent == 8 and line.startswith("- "):
                    close_entry()
                    ev_entry = {"_line": ln}
                    blocker["detail"]["evidence"].append(ev_entry)
                    line = line[2:].strip()
                    indent = 10
                if ev_entry is not None and indent == 10 and ":" in line:
                    key, _, val = line.partition(":")
                    ev_entry[key.strip()] = unquote(val)
                    continue
            errors.append(f"yaml:{ln}: unexpected indent {indent} in blockers: {line}")
            continue

        errors.append(f"yaml:{ln}: line outside any section: {line}")
    return doc


def quote_corpus(ticket_path, errors):
    """Human content of the ticket, keyed by source name. Marker comments
    (body contains 'recon-triage') are pipeline output — excluded."""
    try:
        t = json.loads(ticket_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        errors.append(f"ticket.json unreadable: {e}")
        return {}, set()
    f = t.get("fields", {})
    corpus, markers = {}, set()
    corpus["summary"] = normalize(f.get("summary") or "")
    corpus["description"] = normalize(f.get("description") or "")
    for c in (f.get("comment") or {}).get("comments", []):
        key = f"comment {c.get('id')}"
        if "recon-triage" in (c.get("body") or ""):
            markers.add(key)
        else:
            corpus[key] = normalize(c.get("body") or "")
    return corpus, markers


def check_evidence_entries(entries, where, corpus, markers, errors):
    verified = 0
    for e in entries:
        ln = e.get("_line", "?")
        kind = e.get("kind", "")
        if kind not in EVIDENCE_KINDS:
            errors.append(f"{where} (yaml:{ln}): evidence entry needs kind ∈ "
                          f"{sorted(EVIDENCE_KINDS)} (got '{kind or 'untyped'}')")
            continue
        text = e.get("text", "")
        if not text:
            errors.append(f"{where} (yaml:{ln}): evidence entry has empty text")
            continue
        if kind != "quote":
            continue
        source = e.get("source", "")
        if not source:
            errors.append(f"{where} (yaml:{ln}): quote needs source: "
                          f"summary | description | comment <id>")
            continue
        if source in markers:
            errors.append(f"{where} (yaml:{ln}): quote cites {source}, a recon "
                          f"marker comment — pipeline output is not evidence")
            continue
        if source not in corpus:
            errors.append(f"{where} (yaml:{ln}): quote source '{source}' not in "
                          f"ticket.json (have: summary, description, "
                          f"{len(corpus) - 2} human comment(s))")
            continue
        if normalize(text) not in corpus[source]:
            errors.append(f"{where} (yaml:{ln}): quote not found verbatim in "
                          f"{source}: \"{text[:80]}\"")
            continue
        verified += 1
    return verified


def derive_disposition(s):
    hard_fail = (s.get("evidence_ok") == "false"
                 or s.get("product_decision_open") == "true"
                 or s.get("design_dependency") == "true"
                 or s.get("backend_dependency") == "true")
    if hard_fail:
        return "BLOCKED"
    if s.get("outcome_decidable") in ("partial", "false"):
        return "NEEDS_INFO"
    return "READY"


def cmd_verify(ws):
    yaml_path = ws / "triage" / "triage.yaml"
    ticket_path = ws / "triage" / "ticket.json"
    if not yaml_path.is_file():
        print(f"no triage.yaml: {yaml_path}", file=sys.stderr)
        return 2
    if not ticket_path.is_file():
        print(f"no ticket.json: {ticket_path} (quotes cannot be verified)", file=sys.stderr)
        return 2

    errors = []
    doc = parse_triage(yaml_path, errors)
    s = doc["scalars"]

    for key in REQUIRED_SCALARS:
        if not s.get(key):
            errors.append(f"schema: missing required field '{key}'")
    for key, allowed in SCALAR_ENUMS.items():
        if s.get(key) and s[key] not in allowed:
            errors.append(f"schema: {key}='{s[key]}' not in {sorted(allowed)}")

    disposition = s.get("disposition", "")
    n = len(doc["blockers"])
    if all(s.get(k) in v for k, v in SCALAR_ENUMS.items()):
        derived = derive_disposition(s)
        if derived != disposition:
            failing = []
            if s["evidence_ok"] == "false":
                failing.append("evidence_ok=false")
            for k in ("product_decision_open", "design_dependency", "backend_dependency"):
                if s[k] == "true":
                    failing.append(f"{k}=true")
            errors.append(f"disposition: checks derive {derived} "
                          f"(failing: {', '.join(failing) or 'none'}; "
                          f"outcome_decidable={s['outcome_decidable']}), "
                          f"triage.yaml says {disposition} — fix the checks, "
                          f"never hand-edit the verdict")
        if derived in ("BLOCKED", "NEEDS_INFO") and n == 0:
            errors.append(f"disposition: {derived} derived but blockers is empty — "
                          f"a failing check needs its owner-question written as a blocker")
        if derived == "READY" and n > 0:
            errors.append(f"disposition: READY derived but {n} blocker(s) present — "
                          f"a blocker means a check above should be failing")

    for i, b in enumerate(doc["blockers"], 1):
        where = f"blocker {i}"
        title = b.get("title", "")
        if not title:
            errors.append(f"{where}: missing title")
        elif len(title.split()) > 5:
            errors.append(f"{where}: title '{title}' is {len(title.split())} words (max 5)")
        if not b.get("owner"):
            errors.append(f"{where}: missing owner")
        ask = b.get("ask", "")
        if not ask.endswith("?"):
            errors.append(f"{where}: ask must end in '?' (got: \"{ask[-40:]}\")")
        if disposition in ("BLOCKED", "NEEDS_INFO"):
            acct = b.get("owner_account_id", "")
            if not acct or " " in acct:
                errors.append(f"{where}: owner_account_id missing or malformed — "
                              f"resolve it (posting path step 1), never guess")

    corpus, markers = quote_corpus(ticket_path, errors)
    quotes = 0
    if not doc["evidence"]:
        errors.append("evidence: top-level evidence list is empty — every check "
                      "needs a typed evidence entry")
    quotes += check_evidence_entries(doc["evidence"], "evidence", corpus, markers, errors)
    for i, b in enumerate(doc["blockers"], 1):
        quotes += check_evidence_entries(b["detail"].get("evidence", []),
                                         f"blocker {i} evidence", corpus, markers, errors)

    if errors:
        for e in errors:
            print(f"VERIFY: {e}")
        return 1
    print(f"verify: clean — disposition {disposition} derived from checks, "
          f"{n} blocker(s), {quotes} quote(s) verified")
    return 0


def cmd_render(ws, ticket):
    yaml_path = ws / "triage" / "triage.yaml"
    meta_path = ws / "meta.yaml"
    if not yaml_path.is_file():
        print(f"no triage.yaml: {yaml_path}", file=sys.stderr)
        return 2
    if not meta_path.is_file():
        print(f"no meta.yaml: {meta_path}", file=sys.stderr)
        return 2

    errors = []
    doc = parse_triage(yaml_path, errors)
    s = doc["scalars"]
    meta = {}
    for raw in meta_path.read_text(encoding="utf-8").splitlines():
        key, sep, val = raw.partition(":")
        if sep:
            meta[key.strip()] = unquote(val)

    disposition = s.get("disposition", "")
    blockers = doc["blockers"]
    if disposition not in ("BLOCKED", "NEEDS_INFO"):
        errors.append(f"render: disposition is '{disposition}' — the posting path "
                      f"renders only BLOCKED/NEEDS_INFO comments")
    if not blockers:
        errors.append("render: no blockers to render (posting path demands n ≥ 1)")
    version = meta.get("plugin_version", "")
    if not version:
        errors.append("render: meta.yaml has no plugin_version")
    m = re.match(r"(\d{4})-(\d{2})-(\d{2})T", meta.get("started", ""))
    if not m:
        errors.append(f"render: meta.yaml started '{meta.get('started', '')}' is not ISO-8601")

    lines = []
    if not errors:
        date = f"{int(m.group(3))} {MONTHS[int(m.group(2)) - 1]}"
        lines.append(f"h2. Recon triage: {disposition} — {len(blockers)} blocker(s) ({date})")
        for i, b in enumerate(blockers, 1):
            acct = b.get("owner_account_id", "")
            ask = b.get("ask", "")
            title = b.get("title", "")
            if not acct or " " in acct:
                errors.append(f"render: blocker {i} has no owner_account_id — run "
                              f"verify-triage.sh and resolve owners first")
            if not (title and ask):
                errors.append(f"render: blocker {i} missing title or ask")
            lines.append("")
            lines.append(f"*{i}. {title}* — [~accountid:{acct}]: {ask}")
        lines.append("")
        lines.append(f"Full detail, options, and evidence: "
                     f"[^recon-dossier-{ticket}.html] · [^recon-artifacts-{ticket}.zip]")
        lines.append("Reply here — answers on this ticket un-block the pipeline.")
        lines.append(f"~recon-triage v{version}~")

    if errors:
        for e in errors:
            print(f"RENDER: {e}")
        return 1

    out = ws / "triage" / "jira" / "comment.txt"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"rendered: {out} — {sum(1 for l in lines if l)} non-empty lines, "
          f"{len(blockers)} blocker(s)")
    return 0


def main():
    if len(sys.argv) < 3:
        print("usage: triage-tools.py verify <workspace-dir> | "
              "render <workspace-dir> <TICKET>", file=sys.stderr)
        return 2
    mode, ws = sys.argv[1], Path(sys.argv[2])
    if not ws.is_dir():
        print(f"no workspace: {ws}", file=sys.stderr)
        return 2
    if mode == "verify":
        return cmd_verify(ws)
    if mode == "render":
        if len(sys.argv) < 4:
            print("render needs <TICKET>", file=sys.stderr)
            return 2
        return cmd_render(ws, sys.argv[3])
    print(f"unknown mode: {mode}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
