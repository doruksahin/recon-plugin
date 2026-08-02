#!/usr/bin/env python3
"""Mechanical artifact verification shared by the repro and discovery rails.

The accepted formats are deliberately small.  They are model-authored files,
not general YAML or Markdown documents, so accepting a wider dialect would hide
schema drift instead of protecting the handoff boundary.

    python3 artifact-tools.py verify-repro <workspace-dir> <TICKET>
    python3 artifact-tools.py verify-discovery <workspace-dir> <TICKET> \
        <pre-gate|post-gate>
"""

import ast
import json
import re
import struct
import sys
import zlib
from datetime import date, datetime, timezone
from pathlib import Path


REPRO_FIELDS = {
    "recon",
    "ticket",
    "reproduced",
    "start_state",
    "failure_reason",
}
SAFE_EXHIBIT = re.compile(
    r"exhibits/([1-9][0-9]*)-([a-z0-9]+(?:-[a-z0-9]+)*)\.png"
)
EXHIBIT_TOKEN = re.compile(
    r"([^\s\[\]()<>\"']*exhibits/[^\s\[\]()<>\"']+\.png)",
    re.IGNORECASE,
)
STEP_LINE = re.compile(r"^\s*([1-9][0-9]*)\.\s+(\S.*)$")
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
MTIME_TOLERANCE_SECONDS = 2.0

# The recorded proofshot session bundle (vendored 1.6.0 contract — see
# docs/plans/2026-08-02-proofshot-repro-runtime.md). Schema drift in a
# proofshot upgrade must fail here loudly, never pass silently.
SESSION_REQUIRED_FILES = ("session-log.json", "session.webm", "metadata.json")
SESSION_ENTRY_REQUIRED = {"action", "relativeTimeSec", "timestamp"}
SESSION_ENTRY_OPTIONAL = {"element"}
SCREENSHOT_ACTION = re.compile(
    r"^screenshot\s+([1-9][0-9]*)-([a-z0-9]+(?:-[a-z0-9]+)*)\.png$"
)
WEBM_MAGIC = b"\x1a\x45\xdf\xa3"
WEBM_MIN_BYTES = 32
GIT_OBJECT_ID = re.compile(r"(?:[0-9a-f]{40}|[0-9a-f]{64})")

SCENARIO_ID = r"(?:REQ|REG|OPEN)-[1-9][0-9]*"
SCENARIO_HEADING = re.compile(
    rf"^\s{{0,3}}##\s+({SCENARIO_ID})(?=\s|[-—:]|$)",
)
LOOSE_SCENARIO_HEADING = re.compile(
    r"^\s{0,3}(#{1,6})\s+((?:req|reg|open)-[0-9]+)\b", re.IGNORECASE
)
NO_SCENARIOS = re.compile(r"^\s*No scenarios:\s*\S", re.IGNORECASE)
MARKDOWN_HEADING = re.compile(r"^\s{0,3}(#{1,6})\s+(.+?)\s*#*\s*$")
MARKDOWN_FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")
SCENARIO_MARKERS = {
    "Scenario": re.compile(
        r"^\s*(?:>\s*)?(?:[-*]\s+)?(?:\*\*)?Scenario(?:\*\*)?\s*:\s*\S",
        re.IGNORECASE,
    ),
    "Given": re.compile(
        r"^\s*(?:>\s*)?(?:[-*]\s+)?(?:\*\*)?Given(?:\*\*)?(?:\s*:|\s+)\s*\S",
        re.IGNORECASE,
    ),
    "When": re.compile(
        r"^\s*(?:>\s*)?(?:[-*]\s+)?(?:\*\*)?When(?:\*\*)?(?:\s*:|\s+)\s*\S",
        re.IGNORECASE,
    ),
    "Then": re.compile(
        r"^\s*(?:>\s*)?(?:[-*]\s+)?(?:\*\*)?Then(?:\*\*)?(?:\s*:|\s+)\s*\S",
        re.IGNORECASE,
    ),
}
CHECKBOX = re.compile(r"^\s*[-*+]\s+\[[ xX]\]\s+(\S.*)$")
CHECKBOX_ID = re.compile(rf"^(?:\*\*|`)?({SCENARIO_ID})(?:\*\*|`)?(?=\s|[-—:]|$)")
PROBLEM_ENTRY_ID = re.compile(
    rf"^\s{{0,3}}(?:[-*+]\s+)?(?:\*\*|`)?({SCENARIO_ID})"
    rf"(?:\*\*|`)?(?=\s|[-—:]|$)"
)
STABLE_ID_TOKEN = re.compile(rf"\b({SCENARIO_ID})\b")

ROUTE_BRIEF_KIND = {
    "direct": "none",
    "no-doc": "none",
    "brief": "implementation-brief",
    "amend-spec": "implementation-brief",
    "new-spec": "implementation-brief",
    "escalate": "implementation-brief",
    "prd-chain": "problem-statement",
}
ROUTING_REQUIRED_FIELDS = {
    "route",
    "matched_rule",
    "governance",
    "governance_source",
    "brief_kind",
    "evidence",
    "rules_not_matched",
    "handoff",
}
ROUTING_OPTIONAL_FIELDS = {
    "target",
    "ddd_entry",
    "target_governs",
}
BRIEF_SECTIONS = {
    "implementation-brief": [
        "Overview",
        "Acceptance criteria",
        "Technical design",
        "Integration guardrails",
        "Manual verification",
    ],
    "problem-statement": [
        "Context",
        "Current behavior",
        "Desired outcome",
        "Open choices",
    ],
}


def unquote(raw):
    """Decode the scalar subset used by the fixed artifact schemas."""
    value = raw.strip()
    if value in {"", "null", "Null", "NULL", "~"}:
        return ""
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        try:
            decoded = ast.literal_eval(value)
        except (SyntaxError, ValueError):
            return value[1:-1]
        return str(decoded)
    return value


def read_text(path, label):
    try:
        return path.read_text(encoding="utf-8"), None
    except UnicodeDecodeError as exc:
        return "", f"{label} is not UTF-8: {exc}"
    except OSError as exc:
        return "", f"cannot read {label}: {exc}"


def validate_existing_path(path, allowed_root, label, expected_kind, errors):
    """Return True for a safe existing path, None when absent, False when the
    path exists but is not a regular in-root input.  Check the symlink bit
    before exists()/is_file(): both follow links, including links into runs/ or
    outside the workspace."""
    if path.is_symlink():
        errors.append(f"{label}: symlinks are forbidden")
        return False
    if not path.exists():
        return None
    if expected_kind == "file" and not path.is_file():
        errors.append(f"{label}: expected a regular file")
        return False
    if expected_kind == "directory" and not path.is_dir():
        errors.append(f"{label}: expected a directory")
        return False
    try:
        resolved = path.resolve(strict=True)
        root = allowed_root.resolve(strict=True)
        resolved.relative_to(root)
    except (OSError, RuntimeError, ValueError):
        errors.append(f"{label}: resolved path escapes {allowed_root}")
        return False
    return True


def print_violations(prefix, errors):
    for error in errors:
        print(f"{prefix}: {error}")


def parse_frontmatter(text, errors):
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        errors.append("repro.md must begin with fixed YAML frontmatter")
        return {}, lines
    try:
        end = next(i for i in range(1, len(lines)) if lines[i].strip() == "---")
    except StopIteration:
        errors.append("repro.md frontmatter has no closing ---")
        return {}, []

    values = {}
    for lineno, raw in enumerate(lines[1:end], 2):
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if raw[:1].isspace():
            errors.append(f"repro.md:{lineno}: frontmatter fields must be top-level")
            continue
        key, sep, value = raw.partition(":")
        key = key.strip()
        if not sep or not re.fullmatch(r"[a-z_]+", key):
            errors.append(f"repro.md:{lineno}: invalid frontmatter field")
            continue
        if key in values:
            errors.append(f"repro.md:{lineno}: duplicate frontmatter field '{key}'")
            continue
        values[key] = unquote(value)

    missing = sorted(REPRO_FIELDS - set(values))
    extra = sorted(set(values) - REPRO_FIELDS)
    if missing:
        errors.append("repro.md frontmatter missing: " + ", ".join(missing))
    if extra:
        errors.append("repro.md frontmatter has unknown fields: " + ", ".join(extra))
    return values, lines[end + 1 :]


def parse_started(meta_path, errors):
    text, problem = read_text(meta_path, "meta.yaml")
    if problem:
        errors.append(problem)
        return None
    values = {}
    for lineno, raw in enumerate(text.splitlines(), 1):
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if raw[:1].isspace():
            continue
        key, sep, value = raw.partition(":")
        if sep and key.strip() not in values:
            values[key.strip()] = unquote(value)
        elif sep and key.strip() == "started":
            errors.append(f"meta.yaml:{lineno}: duplicate started field")
    raw_started = values.get("started", "")
    if not raw_started:
        errors.append("meta.yaml has no started timestamp")
        return None
    try:
        parsed = datetime.fromisoformat(raw_started.replace("Z", "+00:00"))
    except ValueError:
        errors.append(f"meta.yaml started is not ISO-8601: '{raw_started}'")
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.timestamp()


def exhibit_tokens(line):
    return [match.group(1) for match in EXHIBIT_TOKEN.finditer(line)]


def validate_png(path, rel, started, errors):
    try:
        data = path.read_bytes()
    except OSError as exc:
        errors.append(f"{rel}: cannot read PNG: {exc}")
        return
    if len(data) < len(PNG_SIGNATURE) or data[:8] != PNG_SIGNATURE:
        errors.append(f"{rel}: invalid PNG signature")
        return

    offset = len(PNG_SIGNATURE)
    chunk_index = 0
    seen_ihdr = False
    seen_plte = False
    seen_idat = False
    idat_ended = False
    seen_iend = False
    idat_parts = []
    width = height = 0
    bit_depth = color_type = None

    while offset < len(data):
        if len(data) - offset < 12:
            errors.append(
                f"{rel}: truncated PNG chunk header/trailer at byte {offset}"
            )
            break
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        chunk_type = data[offset + 4 : offset + 8]
        data_start = offset + 8
        data_end = data_start + length
        chunk_end = data_end + 4
        if chunk_end > len(data):
            name = chunk_type.decode("ascii", "replace")
            errors.append(
                f"{rel}: truncated {name} chunk at byte {offset} "
                f"(declares {length} data byte(s))"
            )
            break
        payload = data[data_start:data_end]
        stored_crc = struct.unpack(">I", data[data_end:chunk_end])[0]
        calculated_crc = zlib.crc32(chunk_type + payload) & 0xFFFFFFFF
        name = chunk_type.decode("ascii", "replace")

        if len(chunk_type) != 4 or not all(
            65 <= byte <= 90 or 97 <= byte <= 122 for byte in chunk_type
        ):
            errors.append(f"{rel}: invalid PNG chunk type {chunk_type!r}")
        if stored_crc != calculated_crc:
            errors.append(f"{rel}: {name} chunk CRC mismatch")
        if chunk_index == 0 and chunk_type != b"IHDR":
            errors.append(f"{rel}: IHDR must be the first PNG chunk")

        if chunk_type == b"IHDR":
            if seen_ihdr or chunk_index != 0:
                errors.append(f"{rel}: PNG must contain exactly one leading IHDR")
            seen_ihdr = True
            if length != 13:
                errors.append(f"{rel}: IHDR must contain exactly 13 data bytes")
            else:
                width, height, bit_depth, color_type, compression, filtering, interlace = (
                    struct.unpack(">IIBBBBB", payload)
                )
                if width < 1 or height < 1:
                    errors.append(
                        f"{rel}: PNG dimensions must both be positive "
                        f"(got {width}x{height})"
                    )
                valid_depths = {
                    0: {1, 2, 4, 8, 16},
                    2: {8, 16},
                    3: {1, 2, 4, 8},
                    4: {8, 16},
                    6: {8, 16},
                }
                if color_type not in valid_depths or bit_depth not in valid_depths[color_type]:
                    errors.append(
                        f"{rel}: invalid IHDR bit-depth/color-type pair "
                        f"{bit_depth}/{color_type}"
                    )
                if compression != 0 or filtering != 0 or interlace not in {0, 1}:
                    errors.append(
                        f"{rel}: invalid IHDR compression/filter/interlace methods"
                    )
        elif not seen_ihdr:
            errors.append(f"{rel}: chunk {name} appears before IHDR")

        if chunk_type == b"PLTE":
            if seen_plte:
                errors.append(f"{rel}: PNG contains more than one PLTE chunk")
            if seen_idat:
                errors.append(f"{rel}: PLTE must appear before IDAT")
            if length == 0 or length > 768 or length % 3:
                errors.append(f"{rel}: PLTE length must be 3..768 and divisible by 3")
            seen_plte = True
        elif chunk_type == b"IDAT":
            if idat_ended:
                errors.append(f"{rel}: IDAT chunks must be consecutive")
            seen_idat = True
            idat_parts.append(payload)
        elif seen_idat and chunk_type != b"IEND":
            idat_ended = True

        if chunk_type == b"IEND":
            seen_iend = True
            if length != 0:
                errors.append(f"{rel}: IEND chunk must be empty")
            if not seen_idat:
                errors.append(f"{rel}: IEND appears before any IDAT chunk")
            if chunk_end != len(data):
                errors.append(f"{rel}: trailing bytes or chunks follow terminal IEND")
            offset = chunk_end
            break

        if chunk_type[:1].isupper() and chunk_type not in {
            b"IHDR", b"PLTE", b"IDAT", b"IEND"
        }:
            errors.append(f"{rel}: unknown critical PNG chunk {name}")

        offset = chunk_end
        chunk_index += 1

    if not seen_ihdr:
        errors.append(f"{rel}: missing IHDR chunk")
    if color_type == 3 and not seen_plte:
        errors.append(f"{rel}: indexed-color PNG requires PLTE before IDAT")
    if color_type in {0, 4} and seen_plte:
        errors.append(f"{rel}: grayscale PNG must not contain PLTE")
    if not seen_idat:
        errors.append(f"{rel}: missing IDAT chunk")
    if not seen_iend:
        errors.append(f"{rel}: missing terminal IEND chunk")
    if seen_iend and offset != len(data):
        errors.append(f"{rel}: PNG parser did not consume the complete file")

    if seen_idat:
        inflater = zlib.decompressobj()
        pending = b"".join(idat_parts)
        try:
            while True:
                output = inflater.decompress(pending, 65536)
                pending = inflater.unconsumed_tail
                if inflater.eof:
                    break
                if pending:
                    continue
                if output:
                    pending = b""
                    continue
                break
        except zlib.error as exc:
            errors.append(f"{rel}: IDAT is not a valid zlib stream: {exc}")
        else:
            if not inflater.eof:
                errors.append(f"{rel}: IDAT zlib stream ends before EOF")
            if inflater.unused_data:
                errors.append(f"{rel}: IDAT contains bytes after the zlib stream")

    if started is not None:
        try:
            modified = path.stat().st_mtime
        except OSError as exc:
            errors.append(f"{rel}: cannot read mtime: {exc}")
            return
        if modified + MTIME_TOLERANCE_SECONDS < started:
            age = int(started - modified)
            errors.append(
                f"{rel}: mtime predates this run by {age}s "
                f"(tolerance {int(MTIME_TOLERANCE_SECONDS)}s)"
            )


def check_session_mtime(path, rel, started, errors):
    if started is None:
        return
    try:
        modified = path.stat().st_mtime
    except OSError as exc:
        errors.append(f"{rel}: cannot read mtime: {exc}")
        return
    if modified + MTIME_TOLERANCE_SECONDS < started:
        age = int(started - modified)
        errors.append(
            f"{rel}: mtime predates this run by {age}s "
            f"(tolerance {int(MTIME_TOLERANCE_SECONDS)}s)"
        )


def parse_session_log(path, rel, started, errors):
    """Validate the proofshot action log; return its entries (or [])."""
    try:
        raw = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        errors.append(f"{rel}: cannot read session log: {exc}")
        return []
    try:
        entries = json.loads(raw)
    except json.JSONDecodeError as exc:
        errors.append(f"{rel}: not valid JSON: {exc}")
        return []
    if not isinstance(entries, list):
        errors.append(f"{rel}: session log must be a JSON array of entries")
        return []
    previous = None
    for index, entry in enumerate(entries):
        label = f"{rel} entry {index}"
        if not isinstance(entry, dict):
            errors.append(f"{label}: must be an object")
            continue
        keys = set(entry)
        missing = sorted(SESSION_ENTRY_REQUIRED - keys)
        unknown = sorted(keys - SESSION_ENTRY_REQUIRED - SESSION_ENTRY_OPTIONAL)
        if missing:
            errors.append(f"{label}: missing key(s) {', '.join(missing)}")
        if unknown:
            errors.append(
                f"{label}: unexpected key(s) {', '.join(unknown)} — "
                "proofshot log schema drift; re-pin the recorder version"
            )
        action = entry.get("action")
        if not isinstance(action, str) or not action.strip():
            errors.append(f"{label}: action must be a non-empty string")
        relative = entry.get("relativeTimeSec")
        if not isinstance(relative, (int, float)) or isinstance(relative, bool) \
                or relative < 0:
            errors.append(f"{label}: relativeTimeSec must be a number >= 0")
        elif previous is not None and relative < previous:
            errors.append(
                f"{label}: relativeTimeSec decreases ({relative} after {previous})"
            )
        else:
            previous = relative
        stamp = entry.get("timestamp")
        if not isinstance(stamp, str):
            errors.append(f"{label}: timestamp must be an ISO-8601 string")
        else:
            try:
                parsed = datetime.fromisoformat(stamp.replace("Z", "+00:00"))
            except ValueError:
                errors.append(f"{label}: timestamp is not ISO-8601: '{stamp}'")
            else:
                if parsed.tzinfo is None:
                    parsed = parsed.replace(tzinfo=timezone.utc)
                if started is not None and (
                    parsed.timestamp() + MTIME_TOLERANCE_SECONDS < started
                ):
                    age = int(started - parsed.timestamp())
                    errors.append(
                        f"{label}: timestamp predates this run by {age}s "
                        f"(tolerance {int(MTIME_TOLERANCE_SECONDS)}s)"
                    )
    return [entry for entry in entries if isinstance(entry, dict)]


def validate_session(repro_dir, reproduced, exhibit_files, started, errors):
    """Verify the recorded session bundle at repro/session/.

    reproduced true REQUIRES the bundle and pairs every exhibit with a logged
    screenshot action; reproduced false permits an absent bundle (the app may
    never have booted) and validates a present one structurally only.
    """
    session_dir = repro_dir / "session"
    path_errors = []
    state = validate_existing_path(
        session_dir, repro_dir, "repro/session/", "directory", path_errors
    )
    if state is None:
        if reproduced == "true":
            errors.append(
                "successful repro requires the recorded session bundle at "
                "repro/session/ (run record-repro.sh start/exec/stop)"
            )
        return
    errors.extend(path_errors)
    if state is not True:
        return

    session_files = {}
    for path in sorted(session_dir.rglob("*")):
        rel = "session/" + path.relative_to(session_dir).as_posix()
        state = validate_existing_path(path, session_dir, rel, "file", errors)
        if state is not True:
            continue
        session_files[path.name] = path
        check_session_mtime(path, rel, started, errors)

    for name in SESSION_REQUIRED_FILES:
        if name not in session_files:
            errors.append(f"session/{name}: required session file is missing")

    metadata = session_files.get("metadata.json")
    if metadata is not None:
        try:
            parsed = json.loads(metadata.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
            errors.append(f"session/metadata.json: not valid JSON: {exc}")
        else:
            if not isinstance(parsed, dict) or not isinstance(
                parsed.get("startedAt"), str
            ):
                errors.append(
                    "session/metadata.json: must be an object with a "
                    "startedAt string"
                )

    video = session_files.get("session.webm")
    if video is not None:
        try:
            head = video.read_bytes()
        except OSError as exc:
            errors.append(f"session/session.webm: cannot read video: {exc}")
        else:
            if len(head) < WEBM_MIN_BYTES:
                errors.append(
                    f"session/session.webm: implausibly small "
                    f"({len(head)} byte(s) < {WEBM_MIN_BYTES})"
                )
            if head[: len(WEBM_MAGIC)] != WEBM_MAGIC:
                errors.append(
                    "session/session.webm: missing EBML magic — not a webm "
                    "recording"
                )

    log = session_files.get("session-log.json")
    entries = []
    if log is not None:
        entries = parse_session_log(log, "session/session-log.json", started, errors)

    if reproduced != "true":
        return

    shot_indices = {}
    for index, entry in enumerate(entries):
        action = entry.get("action")
        if not isinstance(action, str):
            continue
        match = SCREENSHOT_ACTION.match(action.strip())
        if match:
            name = f"{match.group(1)}-{match.group(2)}.png"
            shot_indices[name] = index

    for rel in sorted(exhibit_files):
        name = rel[len("exhibits/"):]
        if name not in shot_indices:
            errors.append(
                f"{rel}: no matching screenshot action in "
                "session-log.json — the exhibit was not produced by the "
                "recorded session"
            )
    exhibit_names = {rel[len("exhibits/"):] for rel in exhibit_files}
    for name in sorted(shot_indices):
        if name not in exhibit_names:
            errors.append(
                f"session-log.json records 'screenshot {name}' but "
                f"repro/exhibits/{name} does not exist"
            )

    ordered = [
        (int(name.split("-", 1)[0]), shot_indices[name])
        for name in shot_indices
        if name in exhibit_names
    ]
    ordered.sort()
    log_positions = [index for _, index in ordered]
    if log_positions != sorted(log_positions):
        errors.append(
            "screenshot actions in session-log.json are out of step order"
        )


def verify_repro(workspace, ticket):
    repro_dir = workspace / "repro"
    repro_path = workspace / "repro" / "repro.md"
    meta_path = workspace / "meta.yaml"
    exhibit_dir = workspace / "repro" / "exhibits"

    path_errors = []
    repro_dir_state = validate_existing_path(
        repro_dir, workspace, "repro/", "directory", path_errors
    )
    if repro_dir_state is None:
        print(f"missing repro/: {repro_dir}", file=sys.stderr)
        return 2
    if repro_dir_state is False:
        print_violations("REPRO", path_errors)
        return 1
    for path, root, label in (
        (repro_path, repro_dir, "repro/repro.md"),
        (meta_path, workspace, "meta.yaml"),
    ):
        state = validate_existing_path(path, root, label, "file", path_errors)
        if state is None:
            print(f"missing {label}: {path}", file=sys.stderr)
            return 2
    exhibit_state = validate_existing_path(
        exhibit_dir, repro_dir, "repro/exhibits/", "directory", path_errors
    )
    if path_errors:
        print_violations("REPRO", path_errors)
        return 1

    errors = []
    text, problem = read_text(repro_path, "repro/repro.md")
    if problem:
        errors.append(problem)
        text = ""
    frontmatter, body = parse_frontmatter(text, errors)
    started = parse_started(meta_path, errors)

    if frontmatter.get("recon") != "repro":
        errors.append("repro.md frontmatter recon must be 'repro'")
    if frontmatter.get("ticket") != ticket:
        errors.append(
            f"repro.md ticket is '{frontmatter.get('ticket', '')}', expected '{ticket}'"
        )
    reproduced = frontmatter.get("reproduced", "")
    if reproduced not in {"true", "false"}:
        errors.append("repro.md reproduced must be true or false")
    if not frontmatter.get("start_state", "").strip():
        errors.append("repro.md start_state must be non-empty")
    failure_reason = frontmatter.get("failure_reason", "").strip()
    if reproduced == "true" and failure_reason:
        errors.append("successful repro must leave failure_reason empty")
    if reproduced == "false" and not failure_reason:
        errors.append("failed repro requires a non-empty failure_reason")

    rendered_body, _ = markdown_line_views(body)
    steps = []
    all_tokens = []
    for lineno, line in enumerate(rendered_body, 1):
        tokens = exhibit_tokens(line)
        all_tokens.extend((lineno, token) for token in tokens)
        match = STEP_LINE.match(line)
        if match:
            steps.append((int(match.group(1)), lineno, match.group(2), tokens))
        elif tokens:
            for token in tokens:
                errors.append(
                    f"repro.md body line {lineno}: exhibit reference outside a "
                    f"numbered step: '{token}'"
                )

    for lineno, token in all_tokens:
        match = SAFE_EXHIBIT.fullmatch(token)
        if not match:
            errors.append(
                f"repro.md body line {lineno}: unsafe exhibit reference '{token}' "
                "(expected exhibits/<n>-<lowercase-slug>.png)"
            )

    exhibit_files = {}
    if exhibit_state is True:
        for path in sorted(exhibit_dir.rglob("*")):
            rel = "exhibits/" + path.relative_to(exhibit_dir).as_posix()
            state = validate_existing_path(
                path, exhibit_dir, rel, "file", errors
            )
            if state is not True:
                continue
            if path.suffix.lower() != ".png":
                errors.append(f"{rel}: unexpected non-PNG file in exhibits")
                continue
            exhibit_files[rel] = path
            if not SAFE_EXHIBIT.fullmatch(rel):
                errors.append(
                    f"{rel}: unsafe exhibit filename "
                    "(expected exhibits/<n>-<lowercase-slug>.png)"
                )

    if reproduced == "true":
        if not steps:
            errors.append("successful repro requires at least one numbered step")
        actual_numbers = [number for number, _, _, _ in steps]
        expected_numbers = list(range(1, len(steps) + 1))
        if actual_numbers != expected_numbers:
            errors.append(
                "repro steps must be contiguous 1..n in order "
                f"(got {actual_numbers or 'none'})"
            )
        safe_step_refs = set()
        for number, lineno, _, tokens in steps:
            if len(tokens) != 1:
                errors.append(
                    f"repro.md body line {lineno}: step {number} must reference "
                    f"exactly one exhibit (got {len(tokens)})"
                )
                continue
            match = SAFE_EXHIBIT.fullmatch(tokens[0])
            if match:
                safe_step_refs.add(tokens[0])
                if int(match.group(1)) != number:
                    errors.append(
                        f"repro.md body line {lineno}: step {number} references "
                        f"exhibit {match.group(1)}"
                    )

        missing = sorted(safe_step_refs - set(exhibit_files))
        orphaned = sorted(set(exhibit_files) - safe_step_refs)
        if missing:
            errors.append("missing referenced exhibits: " + ", ".join(missing))
        if orphaned:
            errors.append(
                "orphan exhibits not referenced by numbered repro steps: "
                + ", ".join(orphaned)
            )
        for rel, path in exhibit_files.items():
            validate_png(path, rel, started, errors)

    if reproduced == "false":
        if steps:
            errors.append("failed repro must not contain success steps")
        if all_tokens:
            errors.append("failed repro must not reference success screenshots")
        if exhibit_files:
            errors.append("failed repro must not contain success screenshots")

    validate_session(repro_dir, reproduced, exhibit_files, started, errors)

    if errors:
        for error in errors:
            print(f"REPRO: {error}")
        return 1
    session_note = (
        "session recorded"
        if (repro_dir / "session").is_dir()
        else "no session (honest failure before recording)"
    )
    print(
        f"verify: clean — repro reproduced {reproduced}, "
        f"{len(steps)} step(s), {len(exhibit_files)} exhibit(s), {session_note}"
    )
    return 0


def marker_count(lines, marker):
    return sum(1 for line in lines if SCENARIO_MARKERS[marker].match(line))


def parse_scenarios(text, errors):
    lines = text.splitlines()
    rendered_lines, semantic_lines = markdown_line_views(lines)
    headings = []
    for index, line in enumerate(semantic_lines):
        match = SCENARIO_HEADING.match(line)
        if match:
            headings.append((match.group(1), index))
            continue
        loose = LOOSE_SCENARIO_HEADING.match(line)
        if loose:
            errors.append(
                f"discovery.md:{index + 1}: invalid scenario heading "
                f"'{loose.group(2)}' (expected H2, uppercase namespace, and a "
                "positive integer without leading zero)"
            )

    seen = {}
    scenario_ids = []
    for scenario_id, index in headings:
        if scenario_id in seen:
            errors.append(
                f"discovery.md:{index + 1}: duplicate scenario ID {scenario_id} "
                f"(first at line {seen[scenario_id] + 1})"
            )
        else:
            seen[scenario_id] = index
            scenario_ids.append(scenario_id)

    for position, (scenario_id, start) in enumerate(headings):
        end = headings[position + 1][1] if position + 1 < len(headings) else len(lines)
        block = rendered_lines[start + 1 : end]
        for marker in ("Scenario", "Given", "When", "Then"):
            count = marker_count(block, marker)
            if count == 0:
                errors.append(f"{scenario_id}: missing {marker} content")
            elif marker == "Scenario" and count != 1:
                errors.append(
                    f"{scenario_id}: contains {count} Scenario lines; each ID owns exactly one"
                )

    global_scenarios = marker_count(rendered_lines, "Scenario")
    if global_scenarios and not headings:
        errors.append("discovery.md has Scenario content without REQ-N/REG-N/OPEN-N headings")
    if global_scenarios != len(headings):
        errors.append(
            f"discovery.md has {global_scenarios} Scenario line(s) for "
            f"{len(headings)} scenario heading(s)"
        )
    no_scenario_lines = [
        index + 1
        for index, line in enumerate(semantic_lines)
        if NO_SCENARIOS.match(line)
    ]
    if headings and no_scenario_lines:
        errors.append("discovery.md cannot mix scenarios with a No scenarios declaration")
    if not headings and not global_scenarios and len(no_scenario_lines) != 1:
        errors.append(
            "discovery.md without scenarios requires exactly one non-empty "
            "'No scenarios:' declaration"
        )
    return scenario_ids


def parse_routing(path, errors):
    text, problem = read_text(path, "route/routing.yaml")
    if problem:
        errors.append(problem)
        return {}
    lines = text.splitlines()
    routing_lines = [
        i
        for i, line in enumerate(lines)
        if line.strip() == "routing:" and not line.startswith(" ")
    ]
    if len(routing_lines) != 1:
        errors.append("routing.yaml must contain exactly one top-level routing: mapping")
        return {}
    start = routing_lines[0]
    for lineno, raw in enumerate(lines[:start], 1):
        if raw.strip() and not raw.lstrip().startswith("#"):
            errors.append(
                f"routing.yaml:{lineno}: content outside the routing: mapping is forbidden"
            )

    def routing_scalar(raw, lineno, label):
        """Decode one scalar in the deliberately small routing dialect.

        Full-line comments are handled by the surrounding parser. Inline YAML
        comments and collection syntax are rejected instead of being mistaken
        for non-empty provenance strings.
        """
        value = raw.strip()
        if not value or value.startswith("#"):
            return ""
        if value[:1] in {"'", '"'} or value[-1:] in {"'", '"'}:
            if len(value) < 2 or value[0] != value[-1]:
                errors.append(
                    f"routing.yaml:{lineno}: {label} has an unterminated quote"
                )
                return ""
            return unquote(value)
        if value.startswith(("[", "{")) or value.endswith(("]", "}")):
            errors.append(
                f"routing.yaml:{lineno}: {label} must be a scalar, not a collection"
            )
            return ""
        if re.search(r"\s#", value):
            errors.append(
                f"routing.yaml:{lineno}: {label} must not use an inline comment"
            )
            return ""
        return unquote(value)

    fields = {}
    allowed_fields = ROUTING_REQUIRED_FIELDS | ROUTING_OPTIONAL_FIELDS
    index = start + 1
    while index < len(lines):
        raw = lines[index]
        if not raw.strip() or raw.lstrip().startswith("#"):
            index += 1
            continue
        if raw and not raw.startswith(" "):
            errors.append(
                f"routing.yaml:{index + 1}: content outside the routing: mapping is forbidden"
            )
            index += 1
            continue
        match = re.match(r"^  ([a-z_]+):\s*(.*)$", raw)
        if not match:
            errors.append(
                f"routing.yaml:{index + 1}: invalid routing field or indentation"
            )
            index += 1
            continue
        key, value = match.group(1), match.group(2).strip()
        duplicate = key in fields
        if duplicate:
            errors.append(f"routing.yaml:{index + 1}: duplicate field '{key}'")
        if key not in allowed_fields:
            errors.append(f"routing.yaml:{index + 1}: unknown routing field '{key}'")
            cursor = index + 1
            while cursor < len(lines):
                following = lines[cursor]
                if following.strip() and len(following) - len(
                    following.lstrip(" ")
                ) <= 2:
                    break
                cursor += 1
            index = cursor
            continue

        if key == "handoff":
            if not re.fullmatch(r"[|>][-+]?", value):
                errors.append(
                    f"routing.yaml:{index + 1}: handoff must use a YAML block scalar"
                )
                if not duplicate:
                    fields[key] = ""
                index += 1
                continue
            block = []
            cursor = index + 1
            while cursor < len(lines):
                following = lines[cursor]
                if following.strip() and len(following) - len(
                    following.lstrip(" ")
                ) <= 2:
                    break
                if following.startswith("    "):
                    block.append(following[4:])
                elif following.strip():
                    errors.append(
                        f"routing.yaml:{cursor + 1}: handoff block needs four-space indent"
                    )
                cursor += 1
            if not duplicate:
                fields[key] = "\n".join(block).strip()
            index = cursor
            continue

        if key in {"evidence", "rules_not_matched"}:
            child_fields = {}
            if value:
                errors.append(
                    f"routing.yaml:{index + 1}: {key} must use an indented mapping"
                )
            cursor = index + 1
            while cursor < len(lines):
                following = lines[cursor]
                if not following.strip() or following.lstrip().startswith("#"):
                    cursor += 1
                    continue
                indentation = len(following) - len(following.lstrip(" "))
                if indentation <= 2:
                    break
                child = re.match(r"^    ([A-Za-z0-9_-]+):\s*(.*)$", following)
                if not child:
                    errors.append(
                        f"routing.yaml:{cursor + 1}: invalid {key} entry or indentation"
                    )
                    cursor += 1
                    continue
                child_key, child_raw = child.group(1), child.group(2).strip()
                child_value = routing_scalar(
                    child_raw,
                    cursor + 1,
                    f"{key}.{child_key}",
                )
                if child_key in child_fields:
                    errors.append(
                        f"routing.yaml:{cursor + 1}: duplicate {key} field "
                        f"'{child_key}'"
                    )
                else:
                    child_fields[child_key] = child_value
                if not child_value.strip() or re.fullmatch(r"[|>][-+]?", child_raw):
                    errors.append(
                        f"routing.yaml:{cursor + 1}: {key}.{child_key} must be "
                        "a non-empty scalar"
                    )
                cursor += 1
            if not duplicate:
                fields[key] = child_fields
            index = cursor
            continue

        if key == "target_governs" and not value:
            items = []
            cursor = index + 1
            while cursor < len(lines):
                following = lines[cursor]
                if not following.strip() or following.lstrip().startswith("#"):
                    cursor += 1
                    continue
                indentation = len(following) - len(following.lstrip(" "))
                if indentation <= 2:
                    break
                item = re.match(r"^    -\s+(\S.*)$", following)
                if not item:
                    errors.append(
                        f"routing.yaml:{cursor + 1}: invalid target_governs list item"
                    )
                else:
                    items.append(
                        routing_scalar(
                            item.group(1),
                            cursor + 1,
                            "target_governs item",
                        )
                    )
                cursor += 1
            if not duplicate:
                fields[key] = items
            index = cursor
            continue

        if key == "target_governs" and not (
            value.startswith("[") and value.endswith("]")
        ):
            errors.append(
                f"routing.yaml:{index + 1}: target_governs must be an inline or "
                "indented list"
            )
        if key == "target_governs":
            if not duplicate:
                fields[key] = value
            index += 1
            continue
        if not duplicate:
            fields[key] = routing_scalar(value, index + 1, f"routing.{key}")
        index += 1

    route = fields.get("route", "")
    brief_kind = fields.get("brief_kind", "")
    handoff = fields.get("handoff", "")
    if route not in ROUTE_BRIEF_KIND:
        errors.append(
            f"routing.route must be one of {', '.join(sorted(ROUTE_BRIEF_KIND))} "
            f"(got '{route or 'missing'}')"
        )
    if brief_kind not in BRIEF_SECTIONS and brief_kind != "none":
        errors.append(
            "routing.brief_kind must be implementation-brief, problem-statement, or none "
            f"(got '{brief_kind or 'missing'}')"
        )
    if route in ROUTE_BRIEF_KIND and brief_kind and ROUTE_BRIEF_KIND[route] != brief_kind:
        errors.append(
            f"routing route '{route}' requires brief_kind '{ROUTE_BRIEF_KIND[route]}', "
            f"got '{brief_kind}'"
        )
    for key in ("matched_rule", "governance", "governance_source"):
        if not str(fields.get(key, "")).strip():
            errors.append(f"routing.{key} must be non-empty")
    evidence = fields.get("evidence")
    if not isinstance(evidence, dict):
        errors.append("routing.evidence must be an indented mapping")
    elif not str(evidence.get("repo_commit", "")).strip():
        errors.append("routing.evidence.repo_commit must be non-empty")
    elif not GIT_OBJECT_ID.fullmatch(str(evidence["repo_commit"])):
        errors.append(
            "routing.evidence.repo_commit must be a full 40- or 64-character "
            "lowercase Git object ID"
        )
    rules_not_matched = fields.get("rules_not_matched")
    if not isinstance(rules_not_matched, dict) or not rules_not_matched:
        errors.append("routing.rules_not_matched must be a non-empty mapping")
    elif any(not str(reason).strip() for reason in rules_not_matched.values()):
        errors.append("routing.rules_not_matched reasons must be non-empty")
    if not handoff:
        errors.append("routing.handoff must be non-empty")
    return fields


def normalize_heading(value):
    value = re.sub(r"[`*_]", "", value)
    value = re.sub(r"\s+", " ", value).strip().rstrip(":")
    return value.casefold()


def mask_html_comments(line, in_comment):
    """Remove non-rendered HTML comments while retaining visible line text."""
    visible = []
    offset = 0
    while offset < len(line):
        if in_comment:
            end = line.find("-->", offset)
            if end < 0:
                return "".join(visible), True
            offset = end + 3
            in_comment = False
            continue
        start = line.find("<!--", offset)
        if start < 0:
            visible.append(line[offset:])
            break
        visible.append(line[offset:start])
        offset = start + 4
        in_comment = True
    return "".join(visible), in_comment


def indented_code_line(line):
    """Return true when leading Markdown whitespace reaches a code indent."""
    columns = 0
    for character in line:
        if character == " ":
            columns += 1
        elif character == "\t":
            columns += 4 - (columns % 4)
        else:
            break
        if columns >= 4:
            return True
    return False


def markdown_line_views(lines):
    """Return rendered and semantic views with stable source line positions.

    The rendered view masks HTML comments outside code fences. The semantic
    view additionally removes fenced and indented code so examples cannot act
    as structural headings, scenario entries, or acceptance checkboxes.
    """
    if isinstance(lines, str):
        lines = lines.splitlines()
    else:
        lines = list(lines)

    rendered = []
    semantic = []
    in_comment = False
    fence_character = ""
    fence_length = 0

    for raw_line in lines:
        if fence_character:
            rendered.append(raw_line)
            semantic.append("")
            closing = re.match(
                rf"^ {{0,3}}{re.escape(fence_character)}{{{fence_length},}}[ \t]*$",
                raw_line,
            )
            if closing:
                fence_character = ""
                fence_length = 0
            continue

        visible_line, in_comment = mask_html_comments(raw_line, in_comment)
        rendered.append(visible_line)

        opening = MARKDOWN_FENCE.match(visible_line)
        if opening and not (
            opening.group(1).startswith("`") and "`" in opening.group(2)
        ):
            marker = opening.group(1)
            fence_character = marker[0]
            fence_length = len(marker)
            semantic.append("")
        elif indented_code_line(visible_line):
            semantic.append("")
        else:
            semantic.append(visible_line)

    return rendered, semantic


def markdown_sections(text):
    lines = text.splitlines()
    rendered_lines, semantic_lines = markdown_line_views(lines)
    headings = []
    for index, line in enumerate(semantic_lines):
        match = MARKDOWN_HEADING.match(line)
        if match:
            headings.append(
                (
                    normalize_heading(match.group(2)),
                    match.group(2).strip(),
                    index,
                    len(match.group(1)),
                )
            )
    sections = {}
    for position, (normalized, raw, start, level) in enumerate(headings):
        end = headings[position + 1][2] if position + 1 < len(headings) else len(lines)
        sections.setdefault(normalized, []).append(
            (
                raw,
                start,
                semantic_lines[start + 1 : end],
                level,
                rendered_lines[start + 1 : end],
            )
        )
    return sections


def nonempty_section(lines):
    return any(line.strip() for line in lines)


def verify_brief(path, brief_kind, scenario_ids, errors):
    text, problem = read_text(path, "discovery/spec-draft.md")
    if problem:
        errors.append(problem)
        return {}
    sections = markdown_sections(text)
    for required in BRIEF_SECTIONS[brief_kind]:
        matches = sections.get(normalize_heading(required), [])
        if not matches:
            errors.append(f"spec-draft.md missing required section '{required}'")
            continue
        if len(matches) > 1:
            errors.append(f"spec-draft.md repeats required section '{required}'")
        if matches[0][3] != 2:
            errors.append(f"spec-draft.md section '{required}' must be an H2 heading")
        if not nonempty_section(matches[0][4]):
            errors.append(f"spec-draft.md section '{required}' is empty")

    if brief_kind != "implementation-brief":
        _, semantic_lines = markdown_line_views(text)
        expected = set(scenario_ids)
        represented = {
            scenario_id
            for line in semantic_lines
            for scenario_id in STABLE_ID_TOKEN.findall(line)
        }
        extra = sorted(represented - expected)
        entry_lines = {}
        current_h2 = None
        for line in semantic_lines:
            heading = MARKDOWN_HEADING.match(line)
            if heading:
                level = len(heading.group(1))
                if level == 2:
                    current_h2 = normalize_heading(heading.group(2))
                elif level == 1:
                    current_h2 = None
                continue
            entry = PROBLEM_ENTRY_ID.match(line)
            if entry:
                entry_lines.setdefault(entry.group(1), []).append(
                    (current_h2, line.strip())
                )

        narrative_sections = {
            normalize_heading("Context"),
            normalize_heading("Current behavior"),
            normalize_heading("Desired outcome"),
        }
        open_section = normalize_heading("Open choices")
        missing = []
        open_entries = {}
        for scenario_id in sorted(expected):
            records = entry_lines.get(scenario_id, [])
            allowed_sections = (
                {open_section}
                if scenario_id.startswith("OPEN-")
                else narrative_sections
            )
            allowed_records = [
                line for section, line in records if section in allowed_sections
            ]
            if not allowed_records:
                missing.append(scenario_id)
            if len(records) > 1:
                errors.append(
                    f"problem statement {scenario_id} must have exactly one visible "
                    f"entry (got {len(records)})"
                )
            elif not allowed_records:
                if scenario_id.startswith("OPEN-"):
                    errors.append(
                        f"problem statement {scenario_id} must have an entry in "
                        "the Open choices section"
                    )
                else:
                    errors.append(
                        f"problem statement {scenario_id} must have an entry in "
                        "Context, Current behavior, or Desired outcome"
                    )
            elif scenario_id.startswith("OPEN-") and len(allowed_records) == 1:
                open_entries[scenario_id] = allowed_records[0]

        if missing:
            errors.append(
                "problem statement missing scenario IDs: " + ", ".join(missing)
            )
        if extra:
            errors.append(
                "problem statement has unknown scenario IDs: " + ", ".join(extra)
            )
        return open_entries
    acceptance = sections.get(normalize_heading("Acceptance criteria"), [])
    if not acceptance:
        return {}
    checkbox_ids = []
    brief_entries = {}
    for offset, line in enumerate(acceptance[0][2], acceptance[0][1] + 2):
        checkbox = CHECKBOX.match(line)
        if not checkbox:
            continue
        id_match = CHECKBOX_ID.match(checkbox.group(1))
        if not id_match:
            errors.append(
                f"spec-draft.md:{offset}: acceptance checkbox must begin with a "
                "REQ-N/REG-N/OPEN-N ID"
            )
            continue
        scenario_id = id_match.group(1)
        checkbox_ids.append(scenario_id)
        brief_entries.setdefault(scenario_id, checkbox.group(1))

    duplicate_ids = sorted({item for item in checkbox_ids if checkbox_ids.count(item) > 1})
    if duplicate_ids:
        errors.append("duplicate acceptance checkbox IDs: " + ", ".join(duplicate_ids))
    scenario_set = set(scenario_ids)
    checkbox_set = set(checkbox_ids)
    missing = sorted(scenario_set - checkbox_set)
    extra = sorted(checkbox_set - scenario_set)
    if missing:
        errors.append("acceptance criteria missing scenario IDs: " + ", ".join(missing))
    if extra:
        errors.append("acceptance criteria has unknown scenario IDs: " + ", ".join(extra))
    return brief_entries


def verify_manual_repro_sync(workspace, brief_path, errors):
    """Prove that a brief consuming repro evidence was authored from that evidence."""
    repro_path = workspace / "repro" / "repro.md"
    if not repro_path.is_file():
        return

    repro_text, repro_problem = read_text(repro_path, "repro/repro.md")
    brief_text, brief_problem = read_text(brief_path, "discovery/spec-draft.md")
    if repro_problem:
        errors.append(repro_problem)
        return
    if brief_problem:
        errors.append(brief_problem)
        return

    frontmatter, body = parse_frontmatter(repro_text, errors)
    manual_sections = markdown_sections(brief_text).get(
        normalize_heading("Manual verification"), []
    )
    if not manual_sections:
        return
    manual_text = "\n".join(line.strip() for line in manual_sections[0][4])

    start_state = frontmatter.get("start_state", "").strip()
    if start_state and start_state not in manual_text:
        errors.append("Manual verification does not copy repro.start_state")

    reproduced = frontmatter.get("reproduced", "")
    if reproduced == "true":
        rendered_body, _ = markdown_line_views(body)
        repro_steps = [line.strip() for line in rendered_body if STEP_LINE.match(line)]
        for step in repro_steps:
            if step not in manual_text:
                number = STEP_LINE.match(step).group(1)
                errors.append(
                    f"Manual verification does not copy verified repro step {number}"
                )
    elif reproduced == "false":
        failure_reason = frontmatter.get("failure_reason", "").strip()
        if failure_reason and failure_reason not in manual_text:
            errors.append("Manual verification does not copy repro.failure_reason")

    evidence_paths = [repro_path]
    exhibit_dir = workspace / "repro" / "exhibits"
    if exhibit_dir.is_dir():
        evidence_paths.extend(path for path in exhibit_dir.rglob("*") if path.is_file())
    try:
        newest_evidence = max(path.stat().st_mtime for path in evidence_paths)
        brief_mtime = brief_path.stat().st_mtime
    except OSError as exc:
        errors.append(f"cannot compare repro/brief mtimes: {exc}")
    else:
        if brief_mtime + MTIME_TOLERANCE_SECONDS < newest_evidence:
            errors.append(
                "spec-draft.md predates the repro evidence it claims to consume"
            )


def split_inline_entries(value):
    entries = []
    current = []
    quote = None
    escaped = False
    for char in value:
        if escaped:
            current.append(char)
            escaped = False
            continue
        if char == "\\" and quote == '"':
            current.append(char)
            escaped = True
            continue
        if char in {"'", '"'}:
            if quote == char:
                quote = None
            elif quote is None:
                quote = char
            current.append(char)
            continue
        if char == "," and quote is None:
            entries.append("".join(current).strip())
            current = []
            continue
        current.append(char)
    entries.append("".join(current).strip())
    return entries


def parse_inline_resolutions(raw, lineno, errors):
    value = raw.strip()
    if value == "{}":
        return {}
    if not (value.startswith("{") and value.endswith("}")):
        errors.append(
            f"gate.yaml:{lineno}: open_scenario_resolutions must be {{}} or a mapping"
        )
        return {}
    body = value[1:-1].strip()
    try:
        decoded = json.loads(value)
    except json.JSONDecodeError:
        decoded = None
    if isinstance(decoded, dict):
        return {str(key): str(item) for key, item in decoded.items()}

    result = {}
    for entry in split_inline_entries(body):
        key, sep, item = entry.partition(":")
        key = unquote(key)
        item = unquote(item)
        if not sep or not key:
            errors.append(f"gate.yaml:{lineno}: invalid inline resolution '{entry}'")
            continue
        if key in result:
            errors.append(f"gate.yaml:{lineno}: duplicate resolution key {key}")
        result[key] = item
    return result


def parse_gate(path, open_ids, errors):
    text, problem = read_text(path, "discovery/gate.yaml")
    if problem:
        errors.append(problem)
        return {"approved": "", "resolutions": {}}
    lines = text.splitlines()
    gate_lines = [i for i, line in enumerate(lines) if line.strip() == "gate:" and not line.startswith(" ")]
    if len(gate_lines) != 1:
        errors.append("gate.yaml must contain exactly one top-level gate: mapping")
        return {"approved": "", "resolutions": {}}

    fields = {}
    resolutions = None
    in_resolutions = False
    index = gate_lines[0] + 1
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
                errors.append(f"gate.yaml:{index + 1}: duplicate field '{key}'")
            fields[key] = unquote(value)
            in_resolutions = key == "open_scenario_resolutions" and value == ""
            if key == "open_scenario_resolutions" and value:
                resolutions = parse_inline_resolutions(value, index + 1, errors)
            elif key == "open_scenario_resolutions":
                resolutions = {}
            index += 1
            continue
        if in_resolutions:
            entry = re.match(r"^    ([^:]+):\s*(.*)$", raw)
            if entry:
                key = unquote(entry.group(1))
                value = unquote(entry.group(2))
                if key in resolutions:
                    errors.append(f"gate.yaml:{index + 1}: duplicate resolution key {key}")
                resolutions[key] = value
                index += 1
                continue
        errors.append(f"gate.yaml:{index + 1}: invalid indentation or field")
        index += 1

    approved = fields.get("approved", "")
    if approved not in {"true", "false"}:
        errors.append("gate.approved must be true or false")
    raw_date = fields.get("date", "")
    try:
        date.fromisoformat(raw_date)
    except ValueError:
        errors.append(f"gate.date must be YYYY-MM-DD (got '{raw_date or 'missing'}')")
    if resolutions is None:
        errors.append("gate.open_scenario_resolutions is required")
        resolutions = {}

    for key, value in resolutions.items():
        if not re.fullmatch(r"OPEN-[1-9][0-9]*", key):
            errors.append(f"gate resolution key '{key}' is not an OPEN-N ID")
        if not str(value).strip():
            errors.append(f"gate resolution {key} must be non-empty")
    expected = set(open_ids)
    actual = set(resolutions)
    missing = sorted(expected - actual)
    extra = sorted(actual - expected)
    if missing:
        errors.append("gate missing OPEN resolutions: " + ", ".join(missing))
    if extra:
        errors.append("gate has resolutions for unknown OPEN IDs: " + ", ".join(extra))

    rejected = fields.get("rejected", "").strip()
    if approved == "false" and not rejected:
        errors.append("rejected gate requires a non-empty rejected reason")
    if approved == "true" and rejected:
        errors.append("approved gate must not contain a rejected reason")
    return {"approved": approved, "resolutions": resolutions}


def verify_discovery(workspace, ticket, mode):
    discovery_dir = workspace / "discovery"
    route_dir = workspace / "route"
    repro_dir = workspace / "repro"
    discovery_path = discovery_dir / "discovery.md"
    routing_path = route_dir / "routing.yaml"
    brief_path = discovery_dir / "spec-draft.md"
    gate_path = discovery_dir / "gate.yaml"
    repro_path = repro_dir / "repro.md"
    exhibit_dir = repro_dir / "exhibits"

    path_errors = []
    for path, label in ((discovery_dir, "discovery/"), (route_dir, "route/")):
        state = validate_existing_path(
            path, workspace, label, "directory", path_errors
        )
        if state is None:
            print(f"missing {label}: {path}", file=sys.stderr)
            return 2
    if path_errors:
        print_violations("DISCOVERY", path_errors)
        return 1
    for path, root, label in (
        (discovery_path, discovery_dir, "discovery/discovery.md"),
        (routing_path, route_dir, "route/routing.yaml"),
    ):
        state = validate_existing_path(path, root, label, "file", path_errors)
        if state is None:
            print(f"missing {label}: {path}", file=sys.stderr)
            return 2
    validate_existing_path(
        brief_path, discovery_dir, "discovery/spec-draft.md", "file", path_errors
    )
    validate_existing_path(
        gate_path, discovery_dir, "discovery/gate.yaml", "file", path_errors
    )

    repro_state = validate_existing_path(
        repro_dir, workspace, "repro/", "directory", path_errors
    )
    if repro_state is True:
        repro_file_state = validate_existing_path(
            repro_path, repro_dir, "repro/repro.md", "file", path_errors
        )
        if repro_file_state is None:
            path_errors.append("repro/ exists without repro/repro.md")
        exhibit_state = validate_existing_path(
            exhibit_dir, repro_dir, "repro/exhibits/", "directory", path_errors
        )
        if exhibit_state is True:
            for path in exhibit_dir.rglob("*"):
                rel = "repro/exhibits/" + path.relative_to(exhibit_dir).as_posix()
                validate_existing_path(
                    path, exhibit_dir, rel, "file", path_errors
                )
    if path_errors:
        print_violations("DISCOVERY", path_errors)
        return 1

    errors = []
    text, problem = read_text(discovery_path, "discovery/discovery.md")
    if problem:
        errors.append(problem)
        text = ""
    scenario_ids = parse_scenarios(text, errors)
    routing = parse_routing(routing_path, errors)
    route = routing.get("route", "")
    brief_kind = routing.get("brief_kind", "")
    brief_entries = {}

    if scenario_ids and route in {"direct", "no-doc"}:
        errors.append(f"route '{route}' cannot discard {len(scenario_ids)} scenario(s)")
    if not scenario_ids and route and route not in {"direct", "no-doc"}:
        errors.append(f"route '{route}' requires a scenario-backed behavior contract")

    if brief_kind == "none":
        if brief_path.exists():
            errors.append("brief_kind none forbids discovery/spec-draft.md")
    elif brief_kind in BRIEF_SECTIONS:
        if not brief_path.is_file():
            print(f"missing discovery/spec-draft.md: {brief_path}", file=sys.stderr)
            return 2
        brief_entries = verify_brief(brief_path, brief_kind, scenario_ids, errors)
        if brief_kind == "implementation-brief":
            verify_manual_repro_sync(workspace, brief_path, errors)

    if mode == "post-gate":
        if not gate_path.is_file():
            print(f"missing discovery/gate.yaml: {gate_path}", file=sys.stderr)
            return 2
        gate = parse_gate(
            gate_path,
            [item for item in scenario_ids if item.startswith("OPEN-")],
            errors,
        )
        if gate["approved"] == "true" and brief_kind in BRIEF_SECTIONS:
            for open_id, resolution in gate["resolutions"].items():
                if resolution not in brief_entries.get(open_id, ""):
                    errors.append(
                        f"approved resolution for {open_id} is not copied verbatim "
                        "into its same-ID brief entry"
                    )

    if errors:
        for error in errors:
            print(f"DISCOVERY: {error}")
        return 1
    open_count = sum(1 for item in scenario_ids if item.startswith("OPEN-"))
    print(
        f"verify: clean — discovery {mode}, {len(scenario_ids)} scenario(s), "
        f"brief_kind {brief_kind}, {open_count} OPEN"
    )
    return 0


def main():
    if len(sys.argv) < 4:
        print(
            "usage: artifact-tools.py verify-repro <workspace-dir> <TICKET> | "
            "verify-discovery <workspace-dir> <TICKET> <pre-gate|post-gate>",
            file=sys.stderr,
        )
        return 2
    command = sys.argv[1]
    workspace = Path(sys.argv[2])
    ticket = sys.argv[3]
    if workspace.is_symlink():
        print(f"ARTIFACT: workspace symlinks are forbidden: {workspace}")
        return 1
    if not workspace.is_dir():
        print(f"no workspace: {workspace}", file=sys.stderr)
        return 2
    if command == "verify-repro" and len(sys.argv) == 4:
        return verify_repro(workspace, ticket)
    if command == "verify-discovery" and len(sys.argv) == 5:
        mode = sys.argv[4]
        if mode not in {"pre-gate", "post-gate"}:
            print("discovery mode must be pre-gate or post-gate", file=sys.stderr)
            return 2
        return verify_discovery(workspace, ticket, mode)
    print("invalid artifact-tools.py arguments", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
