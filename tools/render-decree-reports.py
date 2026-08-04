#!/usr/bin/env python3
"""Regenerate Decree completion reports with portable document identities."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path


DOCUMENT_LINE = re.compile(r"^\*\*Document\*\*: `([^`]+)`$", re.MULTILINE)


def source_for_report(root: Path, report: Path) -> Path:
    doc_id = report.stem.lower()
    candidates = [
        path
        for path in (root / "decree").glob(f"**/{doc_id}-*.md")
        if "reports" not in path.relative_to(root / "decree").parts
    ]
    if len(candidates) != 1:
        raise ValueError(
            f"{report.relative_to(root)}: expected one source for {report.stem}, "
            f"found {len(candidates)}"
        )
    return candidates[0].relative_to(root)


def normalize_reports(root: Path, *, check: bool) -> int:
    failures: list[str] = []
    reports = sorted((root / "decree").glob("*/reports/*.md"))
    for report in reports:
        relative_report = report.relative_to(root)
        try:
            expected_source = source_for_report(root, report).as_posix()
        except ValueError as exc:
            failures.append(str(exc))
            continue
        text = report.read_text(encoding="utf-8")
        match = DOCUMENT_LINE.search(text)
        if not match:
            failures.append(f"{relative_report}: missing Document identity")
            continue
        actual_source = match.group(1)
        if check:
            if Path(actual_source).is_absolute():
                failures.append(f"{relative_report}: absolute host path: {actual_source}")
            elif actual_source != expected_source:
                failures.append(
                    f"{relative_report}: Document identity {actual_source!r} != {expected_source!r}"
                )
            continue
        portable = DOCUMENT_LINE.sub(f"**Document**: `{expected_source}`", text, count=1)
        report.write_text(portable, encoding="utf-8")

    if failures:
        for failure in failures:
            print(f"decree-report: {failure}", file=sys.stderr)
        return 1
    action = "portable" if check else "regenerated and normalized"
    print(f"decree reports: {action} — {len(reports)} report(s)")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--normalize-only", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--root", type=Path, default=Path.cwd(), help=argparse.SUPPRESS)
    args = parser.parse_args()
    root = args.root.resolve()
    if not args.check and not args.normalize_only:
        subprocess.run(
            ["uv", "run", "decree", "report", "regenerate", "--all", "--existing-only"],
            cwd=root,
            check=True,
        )
    return normalize_reports(root, check=args.check)


if __name__ == "__main__":
    raise SystemExit(main())
