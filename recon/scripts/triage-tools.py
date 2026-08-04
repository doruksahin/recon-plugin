#!/usr/bin/env python3
# triage-tools.py — shared engine behind verify-triage.sh (invariant 15) and
# render-comment.sh (invariant 13). Not invoked directly; the bash wrappers
# own argument validation and paths.
#
#   python3 triage-tools.py verify <workspace-dir>
#   python3 triage-tools.py render <workspace-dir> <TICKET>
#   python3 triage-tools.py verify-post-gate <workspace-dir>
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
# verify-post-gate — invariant 18 for the posting gate: the rendered question
#   carried comment.txt verbatim, triage/jira/post-gate.yaml holds one
#   well-formed exchange per presentation (non-empty verbatim answer, known
#   outcome, terminal answer last), and the terminal outcome agrees with what
#   is on disk (posted needs post-result.json; declined forbids the delivery
#   artifacts). It is OUTPUT verification, never evidence for any verdict.
#
# The YAML dialect is the fixed schema in recon-triage SKILL.md step 3 —
# exact two-space indent steps, double-quoted or bare scalars, block lists.
# Parsed by hand on purpose: no PyYAML dependency, and an indentation drift
# that a lenient parser would forgive is itself a schema violation here.
import json
import os
import re
import stat
import sys
from pathlib import Path

MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
          "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
EVIDENCE_KINDS = {"quote", "http", "git", "file", "note"}
DECISION_STATUSES = {
    "OPEN", "CLOSED_BY_TICKET", "CLOSED_BY_REPOSITORY",
    "OPTIONAL_OUT_OF_SCOPE", "IMPLEMENTATION_FREEDOM",
}
DECISION_CHECKS = {
    "product_decision_open", "design_dependency", "backend_dependency",
}
REQUIREMENT_COVERAGE_KEYS = {
    "normative_requirements", "identity_mapping", "context_mapping_exhaustive",
    "ownership_update_path", "threshold_completeness", "ordering_completeness",
}
CLOSURE_SURFACES = {
    "direct_obligation", "identity_mapping", "ownership_update_path",
    "threshold_completeness", "ordering_completeness",
}
CONTEXT_KINDS = {"named", "omitted", "default", "alias"}
CONTEXT_MAPPING_FIELDS = {"context_kind", "context_identity", "observable_result"}
DECISION_ID = re.compile(r"DEC-[1-9][0-9]*\Z")
BLOCKER_ID = re.compile(r"BLK-[1-9][0-9]*\Z")
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

# Posting-gate exchange record (invariant 18): the question is presented from
# the rail-rendered post-gate-questions.txt and every answer is stored in the
# user's own words next to the outcome it was mapped to.
POST_GATE_QUESTIONS_NAME = "post-gate-questions.txt"
POST_GATE_COMMENT_HEADING = "## COMMENT"
POST_GATE_ATTACHMENT_HEADING = "## ATTACHMENTS"
POST_GATE_EXCHANGE_KEYS = {"presented", "answer_verbatim", "outcome"}
POST_GATE_OUTCOMES = {"posted", "edited", "declined"}
POST_GATE_TERMINAL = {"posted", "declined"}


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
    doc = {"scalars": {}, "blockers": [], "conflicts": 0, "evidence": [],
           "requirement_coverage": {}, "decision_audit": [], "sections": set()}
    lines = path.read_text(encoding="utf-8").splitlines()
    section = None      # None | blockers | conflicts | evidence
    blocker = None
    in_detail = False
    detail_list = None  # None | options | evidence
    ev_entry = None     # current typed evidence entry (top-level or detail)
    audit = None
    audit_list = None

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
            audit = None
            in_detail = False
            detail_list = None
            audit_list = None
            key, sep, val = line.partition(":")
            if not sep:
                errors.append(f"yaml:{ln}: unparseable top-level line: {line}")
                continue
            val = val.strip()
            if key in ("blockers", "conflicts", "evidence", "requirement_coverage",
                       "decision_audit"):
                doc["sections"].add(key)
                section = key
                if key == "requirement_coverage" and val:
                    errors.append(f"yaml:{ln}: requirement_coverage must be a block mapping")
                    section = None
                elif val == "[]":
                    section = None
                elif val:
                    errors.append(f"yaml:{ln}: {key} must be a block list or []")
            else:
                section = None
                doc["scalars"][key] = unquote(val)
            continue

        if section == "requirement_coverage":
            if indent == 2 and ":" in line:
                key, _, val = line.partition(":")
                key = key.strip()
                if key in doc["requirement_coverage"]:
                    errors.append(f"yaml:{ln}: duplicate requirement_coverage field '{key}'")
                doc["requirement_coverage"][key] = unquote(val)
                continue
            errors.append(f"yaml:{ln}: unexpected indent {indent} in requirement_coverage: {line}")
            continue

        if section == "decision_audit":
            if indent == 2 and line.startswith("- "):
                close_entry()
                audit_list = None
                audit = {"_line": ln, "evidence": []}
                doc["decision_audit"].append(audit)
                key, sep, val = line[2:].partition(":")
                if key.strip() != "id" or not sep:
                    errors.append(f"yaml:{ln}: decision entries must start '  - id:'")
                else:
                    audit["id"] = unquote(val)
                continue
            if audit is None:
                errors.append(f"yaml:{ln}: content before first '  - id:' in decision_audit")
                continue
            if indent == 4:
                close_entry()
                key, sep, val = line.partition(":")
                key, val = key.strip(), val.strip()
                if key == "evidence":
                    audit_list = "evidence"
                    if val == "[]":
                        audit_list = None
                    elif val:
                        errors.append(f"yaml:{ln}: decision evidence must be a block list or []")
                else:
                    audit_list = None
                    if key in audit:
                        errors.append(f"yaml:{ln}: duplicate decision field '{key}'")
                    audit[key] = unquote(val)
                continue
            if audit_list == "evidence":
                if indent == 6 and line.startswith("- "):
                    close_entry()
                    ev_entry = {"_line": ln}
                    audit["evidence"].append(ev_entry)
                    line = line[2:].strip()
                    indent = 8
                if ev_entry is not None and indent == 8 and ":" in line:
                    key, _, val = line.partition(":")
                    ev_entry[key.strip()] = unquote(val)
                    continue
            errors.append(f"yaml:{ln}: unexpected indent {indent} in decision_audit: {line}")
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


def read_repository_evidence(source_root, path_value):
    """Return UTF-8 lines from a regular in-root file without symlink traversal."""
    relative = Path(path_value)
    candidate = source_root / relative
    current = source_root
    try:
        for part in relative.parts:
            current = current / part
            if stat.S_ISLNK(current.lstat().st_mode):
                return None, f"file evidence path contains a symlink: {path_value}"
    except (FileNotFoundError, NotADirectoryError, OSError):
        return None, f"file evidence path is not a regular file: {path_value}"

    try:
        resolved_candidate = candidate.resolve(strict=True)
        resolved_candidate.relative_to(source_root)
    except (FileNotFoundError, NotADirectoryError, OSError, ValueError):
        return None, f"file evidence path escapes RECON_SOURCE_ROOT: {path_value}"
    if not resolved_candidate.is_file():
        return None, f"file evidence path is not a regular file: {path_value}"
    try:
        return resolved_candidate.read_text(encoding="utf-8").splitlines(), None
    except (OSError, UnicodeError):
        return None, f"file evidence path is not a readable UTF-8 file: {path_value}"


def check_evidence_entries(entries, where, corpus, markers, errors, source_root):
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
        if kind == "file":
            path_value = e.get("path", "")
            line_value = e.get("line", "")
            if not path_value or Path(path_value).is_absolute() or ".." in Path(path_value).parts:
                errors.append(f"{where} (yaml:{ln}): file evidence needs a relative path inside RECON_SOURCE_ROOT")
                continue
            if not str(line_value).isdigit() or int(line_value) < 1:
                errors.append(f"{where} (yaml:{ln}): file evidence needs a positive line")
                continue
            source_lines, path_error = read_repository_evidence(source_root, path_value)
            if path_error:
                errors.append(f"{where} (yaml:{ln}): {path_error}")
                continue
            if int(line_value) > len(source_lines) or normalize(text) != normalize(source_lines[int(line_value) - 1]):
                errors.append(f"{where} (yaml:{ln}): file evidence drift at {path_value}:{line_value}")
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


def validate_decision_audit(doc, corpus, markers, errors, source_root):
    """Verify the persisted closure audit and its atomic blocker join."""
    if "requirement_coverage" not in doc["sections"]:
        errors.append("schema: missing required section 'requirement_coverage'")
    else:
        coverage = doc["requirement_coverage"]
        missing = REQUIREMENT_COVERAGE_KEYS - set(coverage)
        unknown = set(coverage) - REQUIREMENT_COVERAGE_KEYS
        if missing:
            errors.append(f"requirement_coverage: missing field(s) {sorted(missing)}")
        if unknown:
            errors.append(f"requirement_coverage: unknown field(s) {sorted(unknown)}")
        for key in sorted(REQUIREMENT_COVERAGE_KEYS):
            if key in coverage and coverage[key] != "true":
                errors.append(f"requirement_coverage: {key} must be true after the audit")

    if "decision_audit" not in doc["sections"]:
        errors.append("schema: missing required section 'decision_audit'")
        return

    audits = doc["decision_audit"]
    audit_by_id = {}
    context_mappings = set()
    expected_checks = {key: "false" for key in DECISION_CHECKS}
    for index, audit in enumerate(audits, 1):
        where = f"decision {index}"
        decision_id = audit.get("id", "")
        if not DECISION_ID.fullmatch(decision_id):
            errors.append(f"{where}: id must match DEC-N (got '{decision_id or 'missing'}')")
        elif decision_id in audit_by_id:
            errors.append(f"{where}: duplicate decision id {decision_id}")
        else:
            audit_by_id[decision_id] = audit
        requirement = audit.get("requirement", "")
        requirement_source = audit.get("requirement_source", "")
        if not requirement:
            errors.append(f"{where}: requirement must retain the observable obligation")
        if not requirement_source:
            errors.append(f"{where}: requirement_source must name a human ticket source")
        elif requirement_source in markers:
            errors.append(f"{where}: requirement_source {requirement_source} is a recon marker comment — pipeline output is not evidence")
        elif requirement_source not in corpus:
            errors.append(f"{where}: requirement_source '{requirement_source}' not in ticket.json")
        elif requirement and normalize(requirement) not in corpus[requirement_source]:
            errors.append(f"{where}: requirement is not found verbatim in {requirement_source}")
        status = audit.get("status", "")
        if status not in DECISION_STATUSES:
            errors.append(f"{where}: status must be one of {sorted(DECISION_STATUSES)}")
        surface = audit.get("surface", "")
        if surface not in CLOSURE_SURFACES:
            errors.append(f"{where}: surface must be one of {sorted(CLOSURE_SURFACES)}")
        mapping_fields = CONTEXT_MAPPING_FIELDS & set(audit)
        if surface == "identity_mapping":
            missing_mapping = CONTEXT_MAPPING_FIELDS - set(audit)
            if missing_mapping:
                errors.append(f"{where}: identity_mapping missing field(s) {sorted(missing_mapping)}")
            context_kind = audit.get("context_kind", "")
            if context_kind not in CONTEXT_KINDS:
                errors.append(f"{where}: context_kind must be one of {sorted(CONTEXT_KINDS)}")
            context_identity = audit.get("context_identity", "").strip()
            observable_result = audit.get("observable_result", "").strip()
            if not context_identity:
                errors.append(f"{where}: context_identity must name exactly one context")
            if not observable_result:
                errors.append(f"{where}: observable_result must select one result or be UNRESOLVED")
            if status == "OPEN" and observable_result != "UNRESOLVED":
                errors.append(f"{where}: OPEN identity_mapping must set observable_result to UNRESOLVED")
            if status in DECISION_STATUSES - {"OPEN"} and observable_result == "UNRESOLVED":
                errors.append(f"{where}: resolved identity_mapping must select an observable_result")
            mapping_key = (
                requirement_source,
                normalize(requirement),
                context_kind,
                normalize(context_identity),
            )
            if context_kind in CONTEXT_KINDS and context_identity:
                if mapping_key in context_mappings:
                    errors.append(f"{where}: duplicate context mapping for {context_kind} '{context_identity}'")
                else:
                    context_mappings.add(mapping_key)
        elif mapping_fields:
            errors.append(f"{where}: context mapping fields are allowed only on identity_mapping")
        check = audit.get("check", "")
        if check not in DECISION_CHECKS:
            errors.append(f"{where}: check must be one of {sorted(DECISION_CHECKS)}")
        blocking = audit.get("blocking", "")
        if blocking not in {"true", "false"}:
            errors.append(f"{where}: blocking must be true or false")
        elif status != "OPEN" and blocking != "false":
            errors.append(f"{where}: only OPEN decisions may be blocking")
        blocker_id = audit.get("blocker_id", "")
        if status == "OPEN" and blocking == "true":
            if not BLOCKER_ID.fullmatch(blocker_id):
                errors.append(f"{where}: blocking OPEN decision needs blocker_id BLK-N")
            if check in expected_checks:
                expected_checks[check] = "true"
        elif blocker_id:
            errors.append(f"{where}: non-blocking decision must not name a blocker_id")
        unknown = set(audit) - ({"_line", "id", "requirement", "requirement_source", "surface", "status", "check", "blocking", "blocker_id", "evidence"} | CONTEXT_MAPPING_FIELDS)
        if unknown:
            errors.append(f"{where}: unknown field(s) {sorted(unknown)}")
        if not audit["evidence"]:
            errors.append(f"{where}: evidence is empty")
        if status == "CLOSED_BY_REPOSITORY" and not any(
                evidence.get("kind") == "file" for evidence in audit["evidence"]):
            errors.append(f"{where}: CLOSED_BY_REPOSITORY requires cited file evidence")
        for evidence in audit["evidence"]:
            kind = evidence.get("kind", "")
            permitted = ({"_line", "kind", "text", "source"} if kind == "quote" else
                         {"_line", "kind", "text", "path", "line"} if kind == "file" else
                         {"_line", "kind", "text"})
            extras = set(evidence) - permitted
            if extras:
                errors.append(f"{where} evidence (yaml:{evidence.get('_line', '?')}): unknown field(s) {sorted(extras)}")
        check_evidence_entries(audit["evidence"], f"{where} evidence", corpus, markers, errors, source_root)

    blockers_by_id = {}
    for index, blocker in enumerate(doc["blockers"], 1):
        where = f"blocker {index}"
        blocker_id = blocker.get("id", "")
        if not BLOCKER_ID.fullmatch(blocker_id):
            errors.append(f"{where}: id must match BLK-N (got '{blocker_id or 'missing'}')")
        elif blocker_id in blockers_by_id:
            errors.append(f"{where}: duplicate blocker id {blocker_id}")
        else:
            blockers_by_id[blocker_id] = blocker
        decision_id = blocker.get("decision_id", "")
        if not DECISION_ID.fullmatch(decision_id):
            errors.append(f"{where}: decision_id must match DEC-N (got '{decision_id or 'missing'}')")

    for decision_id, audit in audit_by_id.items():
        if audit.get("status") != "OPEN" or audit.get("blocking") != "true":
            continue
        blocker_id = audit.get("blocker_id", "")
        blocker = blockers_by_id.get(blocker_id)
        if blocker is None:
            errors.append(f"decision {decision_id}: blocker_id {blocker_id} has no matching blocker")
        elif blocker.get("decision_id") != decision_id:
            errors.append(f"decision {decision_id}: blocker {blocker_id} points to {blocker.get('decision_id') or 'no decision'}")

    for blocker_id, blocker in blockers_by_id.items():
        decision_id = blocker.get("decision_id", "")
        audit = audit_by_id.get(decision_id)
        if audit is None:
            errors.append(f"blocker {blocker_id}: decision_id {decision_id} has no audited OPEN decision")
        elif audit.get("status") != "OPEN" or audit.get("blocking") != "true":
            errors.append(f"blocker {blocker_id}: decision {decision_id} is not a blocking OPEN decision")
        elif audit.get("blocker_id") != blocker_id:
            errors.append(f"blocker {blocker_id}: decision {decision_id} maps to {audit.get('blocker_id') or 'no blocker'}")

    for check, expected in expected_checks.items():
        actual = doc["scalars"].get(check, "")
        if actual and actual != expected:
            errors.append(f"decision_audit: {check} must be {expected} from blocking OPEN decisions (triage.yaml says {actual})")


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
    source_root = Path(os.environ.get("RECON_SOURCE_ROOT", Path.cwd())).resolve()
    if not source_root.is_dir():
        errors.append(f"RECON_SOURCE_ROOT is not a directory: {source_root}")

    for key in REQUIRED_SCALARS:
        if not s.get(key):
            errors.append(f"schema: missing required field '{key}'")
    for key, allowed in SCALAR_ENUMS.items():
        if s.get(key) and s[key] not in allowed:
            errors.append(f"schema: {key}='{s[key]}' not in {sorted(allowed)}")

    corpus, markers = quote_corpus(ticket_path, errors)
    validate_decision_audit(doc, corpus, markers, errors, source_root)

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

    quotes = 0
    if not doc["evidence"]:
        errors.append("evidence: top-level evidence list is empty — every check "
                      "needs a typed evidence entry")
    quotes += check_evidence_entries(doc["evidence"], "evidence", corpus, markers, errors, source_root)
    for i, b in enumerate(doc["blockers"], 1):
        quotes += check_evidence_entries(b["detail"].get("evidence", []),
                                         f"blocker {i} evidence", corpus, markers, errors, source_root)

    if errors:
        for e in errors:
            print(f"VERIFY: {e}")
        return 1
    print(f"verify: clean — disposition {disposition} derived from checks, "
          f"{n} blocker(s), {quotes} quote(s) verified")
    return 0


def ready_delivery_facts(ws, errors):
    """Read the small fixed subset of an approved Discovery package needed for
    the READY delivery comment. The full package remains in the dossier/bundle;
    the comment is deliberately a short, deterministic index."""
    gate_path = ws / "discovery" / "gate.yaml"
    route_path = ws / "route" / "routing.yaml"
    facts = {"approved": "", "decisions": 0, "route": "", "rule": ""}

    if not gate_path.is_file():
        errors.append(f"render: READY delivery needs discovery/gate.yaml: {gate_path}")
    else:
        for raw in gate_path.read_text(encoding="utf-8").splitlines():
            if raw.startswith("  approved:"):
                facts["approved"] = unquote(raw.partition(":")[2])
            elif re.match(r"^    OPEN-[1-9][0-9]*:\s*\S", raw):
                facts["decisions"] += 1
        if facts["approved"] != "true":
            errors.append("render: READY delivery requires an approved discovery/gate.yaml")

    if not route_path.is_file():
        errors.append(f"render: READY delivery needs route/routing.yaml: {route_path}")
    else:
        for raw in route_path.read_text(encoding="utf-8").splitlines():
            if raw.startswith("  route:"):
                facts["route"] = unquote(raw.partition(":")[2])
            elif raw.startswith("  matched_rule:"):
                facts["rule"] = unquote(raw.partition(":")[2])
        if not facts["route"]:
            errors.append("render: READY delivery route/routing.yaml has no route")
        if not facts["rule"]:
            errors.append("render: READY delivery route/routing.yaml has no matched_rule")
    return facts


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
    version = meta.get("plugin_version", "")
    if not version:
        errors.append("render: meta.yaml has no plugin_version")
    m = re.match(r"(\d{4})-(\d{2})-(\d{2})T", meta.get("started", ""))
    if not m:
        errors.append(f"render: meta.yaml started '{meta.get('started', '')}' is not ISO-8601")

    lines = []
    if disposition in ("BLOCKED", "NEEDS_INFO"):
        if not blockers:
            errors.append("render: no blockers to render (posting path demands n ≥ 1)")
    elif disposition == "READY":
        ready = ready_delivery_facts(ws, errors)
        if blockers:
            errors.append("render: READY delivery requires no blockers")
    else:
        errors.append(f"render: disposition is '{disposition}'")

    if not errors and disposition in ("BLOCKED", "NEEDS_INFO"):
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

    if not errors and disposition == "READY":
        date = f"{int(m.group(3))} {MONTHS[int(m.group(2)) - 1]}"
        decisions = ready["decisions"]
        lines.append(f"h2. Recon discovery: READY — {ready['route']} ({date})")
        lines.append(f"*Outcome:* {s.get('title', '')}")
        lines.append(f"*Approval:* Discovery package approved; {decisions} open decision(s) recorded.")
        lines.append(f"*Route:* {ready['route']} (rule {ready['rule']}).")
        lines.append(f"Full dossier, approved brief, and evidence: "
                     f"[^recon-dossier-{ticket}.html] · [^recon-artifacts-{ticket}.zip]")
        lines.append(f"~recon-triage v{version}~")

    if errors:
        for e in errors:
            print(f"RENDER: {e}")
        return 1

    out = ws / "triage" / "jira" / "comment.txt"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"rendered: {out} — {sum(1 for l in lines if l)} non-empty lines, "
          f"{len(blockers)} blocker(s), disposition {disposition}")
    return 0


def strip_blank_edges(lines):
    out = list(lines)
    while out and not out[0].strip():
        out.pop(0)
    while out and not out[-1].strip():
        out.pop()
    return out


def comment_section(question_lines, errors):
    """The COMMENT block of post-gate-questions.txt, blank edges removed."""
    start = end = None
    for index, line in enumerate(question_lines):
        if line.startswith(POST_GATE_COMMENT_HEADING):
            if start is not None:
                errors.append("post-gate-questions.txt has more than one "
                              "COMMENT section")
                return []
            start = index + 1
        elif line.startswith(POST_GATE_ATTACHMENT_HEADING) and start is not None:
            end = index
            break
    if start is None:
        errors.append("post-gate-questions.txt has no "
                      f"'{POST_GATE_COMMENT_HEADING}' section — re-render it "
                      "with render-post-gate.sh")
        return []
    if end is None:
        errors.append("post-gate-questions.txt has no "
                      f"'{POST_GATE_ATTACHMENT_HEADING}' section after the "
                      "comment — re-render it with render-post-gate.sh")
        return []
    return strip_blank_edges(question_lines[start:end])


def parse_post_gate(path, errors):
    """The posting-gate exchange record — same hand-rolled dialect as above."""
    lines = path.read_text(encoding="utf-8").splitlines()
    roots = [i for i, line in enumerate(lines)
             if line.strip() == "post_gate:" and not line.startswith(" ")]
    if len(roots) != 1:
        errors.append("post-gate.yaml must contain exactly one top-level "
                      "post_gate: mapping")
        return {"date": "", "exchanges": None}

    fields = {}
    exchanges = None
    exchange = None
    in_exchanges = False
    index = roots[0] + 1
    while index < len(lines):
        raw = lines[index]
        if raw and not raw.startswith(" ") and not raw.lstrip().startswith("#"):
            break
        if not raw.strip() or raw.lstrip().startswith("#"):
            index += 1
            continue
        field = re.match(r"^  ([a-z_]+):\s*(.*)$", raw)
        if field:
            key, value = field.group(1), field.group(2).strip()
            if key in fields:
                errors.append(f"post-gate.yaml:{index + 1}: duplicate field '{key}'")
            fields[key] = unquote(value)
            in_exchanges = key == "exchanges"
            if key == "exchanges":
                exchanges = []
                exchange = None
                if value:
                    errors.append(f"post-gate.yaml:{index + 1}: exchanges must "
                                  "be a block list")
            index += 1
            continue
        if in_exchanges:
            entry_start = re.match(r"^    - ([a-z_]+):\s*(.*)$", raw)
            if entry_start:
                key = entry_start.group(1)
                if key != "presented":
                    errors.append(f"post-gate.yaml:{index + 1}: exchange entries "
                                  "must start with 'presented'")
                exchange = {key: unquote(entry_start.group(2).strip())}
                exchanges.append(exchange)
                index += 1
                continue
            entry_field = re.match(r"^      ([a-z_]+):\s*(.*)$", raw)
            if entry_field and exchange is not None:
                key = entry_field.group(1)
                if key not in POST_GATE_EXCHANGE_KEYS:
                    errors.append(f"post-gate.yaml:{index + 1}: unknown exchange "
                                  f"field '{key}'")
                elif key in exchange:
                    errors.append(f"post-gate.yaml:{index + 1}: duplicate "
                                  f"exchange field '{key}'")
                else:
                    exchange[key] = unquote(entry_field.group(2).strip())
                index += 1
                continue
        errors.append(f"post-gate.yaml:{index + 1}: invalid indentation or field")
        index += 1

    raw_date = fields.get("date", "")
    if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", raw_date):
        errors.append("post_gate.date must be YYYY-MM-DD "
                      f"(got '{raw_date or 'missing'}')")
    return {"date": raw_date, "exchanges": exchanges}


def validate_post_gate_exchanges(exchanges, errors):
    """Ordered answers: any number of `edited`, then exactly one terminal."""
    if exchanges is None:
        errors.append("post_gate.exchanges is required (one entry per time the "
                      "gate was presented)")
        return ""
    if not exchanges:
        errors.append("post_gate.exchanges is empty — a presented gate has at "
                      "least one answer")
        return ""
    last = len(exchanges) - 1
    for position, exchange in enumerate(exchanges):
        where = f"exchange {position + 1}"
        presented = exchange.get("presented", "")
        if presented != POST_GATE_QUESTIONS_NAME:
            errors.append(f"{where}: presented must be "
                          f"'{POST_GATE_QUESTIONS_NAME}' (got '{presented}')")
        if not exchange.get("answer_verbatim", "").strip():
            errors.append(f"{where}: answer_verbatim must be non-empty "
                          "(the user's exact words)")
        outcome = exchange.get("outcome", "").strip()
        if outcome not in POST_GATE_OUTCOMES:
            errors.append(f"{where}: outcome '{outcome or 'missing'}' not in "
                          f"{sorted(POST_GATE_OUTCOMES)}")
            continue
        terminal = outcome in POST_GATE_TERMINAL
        if terminal and position != last:
            errors.append(f"{where}: '{outcome}' ends the gate — no exchange "
                          "may follow it")
        if not terminal and position == last:
            errors.append(f"{where}: the last exchange must be "
                          f"{' or '.join(sorted(POST_GATE_TERMINAL))} — an "
                          "'edited' answer means the gate was re-presented")
    final = exchanges[-1].get("outcome", "").strip()
    return final if final in POST_GATE_TERMINAL else ""


def cmd_verify_post_gate(ws):
    jira = ws / "triage" / "jira"
    comment_path = jira / "comment.txt"
    questions_path = jira / POST_GATE_QUESTIONS_NAME
    gate_path = jira / "post-gate.yaml"
    if not comment_path.is_file():
        print(f"no comment draft: {comment_path}", file=sys.stderr)
        return 2
    if not gate_path.is_file():
        print(f"no posting-gate record: {gate_path}", file=sys.stderr)
        return 2

    errors = []
    if not questions_path.is_file():
        errors.append("gate answered without rendered "
                      f"triage/jira/{POST_GATE_QUESTIONS_NAME} (run "
                      "render-post-gate.sh before presenting the gate)")
    else:
        presented_comment = comment_section(
            questions_path.read_text(encoding="utf-8").splitlines(), errors
        )
        drafted_comment = strip_blank_edges(
            comment_path.read_text(encoding="utf-8").splitlines()
        )
        if presented_comment and presented_comment != drafted_comment:
            errors.append("the rendered question does not carry comment.txt "
                          "verbatim — re-render the gate question after every "
                          "comment change")

    record = parse_post_gate(gate_path, errors)
    outcome = validate_post_gate_exchanges(record["exchanges"], errors)

    posted = (jira / "post-result.json").is_file()
    attached = (jira / "attach-result.json").is_file()
    if outcome == "posted" and not posted:
        errors.append("outcome 'posted' but triage/jira/post-result.json is "
                      "absent — the delivery never landed")
    if outcome == "declined":
        if posted:
            errors.append("outcome 'declined' but triage/jira/post-result.json "
                          "exists — a declined gate posts nothing")
        if attached:
            errors.append("outcome 'declined' but triage/jira/attach-result.json "
                          "exists — a declined gate uploads nothing")

    if errors:
        for e in errors:
            print(f"POST-GATE: {e}")
        return 1
    count = len(record["exchanges"] or [])
    print(f"post-gate: clean — {count} exchange(s), outcome {outcome}")
    return 0


def main():
    if len(sys.argv) < 3:
        print("usage: triage-tools.py verify <workspace-dir> | "
              "render <workspace-dir> <TICKET> | "
              "verify-post-gate <workspace-dir>", file=sys.stderr)
        return 2
    mode, ws = sys.argv[1], Path(sys.argv[2])
    if not ws.is_dir():
        print(f"no workspace: {ws}", file=sys.stderr)
        return 2
    if mode == "verify":
        return cmd_verify(ws)
    if mode == "verify-post-gate":
        return cmd_verify_post_gate(ws)
    if mode == "render":
        if len(sys.argv) < 4:
            print("render needs <TICKET>", file=sys.stderr)
            return 2
        return cmd_render(ws, sys.argv[3])
    print(f"unknown mode: {mode}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
