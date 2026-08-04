#!/usr/bin/env python3
"""Regenerate and completely drift-check portable Decree completion reports."""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


DOCUMENT_LINE = re.compile(r"^\*\*Document\*\*: `([^`]+)`$", re.MULTILINE)
GENERATED_LINE = re.compile(r"^\*\*Generated\*\*: .+$", re.MULTILINE)
TRANSITION_LINE = re.compile(
    r"^\*\*Transitioned to `([^`]+)` on\*\*: (\d{4}-\d{2}-\d{2})$", re.MULTILINE
)
DATE_FIELD = re.compile(r"^date:\s*['\"]?([^'\"\s]+)['\"]?\s*$", re.MULTILINE)
STATUS_FIELD = re.compile(r"^status:\s*['\"]?([^'\"\s]+)['\"]?\s*$", re.MULTILINE)
VOLATILE_GENERATED = "**Generated**: <volatile>"


def tracked_report_paths(root: Path) -> tuple[Path, ...]:
    git_env = os.environ.copy()
    for name in (
        "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_PREFIX",
        "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES",
    ):
        git_env.pop(name, None)
    result = subprocess.run(
        ["git", "-C", str(root), "ls-files", "decree/*/reports/*.md"],
        text=True,
        capture_output=True,
        check=True,
        env=git_env,
    )
    return tuple(Path(line) for line in result.stdout.splitlines() if line)


def source_for_report(root: Path, relative_report: Path) -> Path:
    doc_id = relative_report.stem.lower()
    candidates = [
        path
        for path in (root / "decree").glob(f"**/{doc_id}-*.md")
        if "reports" not in path.relative_to(root / "decree").parts
    ]
    if len(candidates) != 1:
        raise ValueError(
            f"{relative_report}: expected one source for {relative_report.stem}, "
            f"found {len(candidates)}"
        )
    return candidates[0].relative_to(root)


def source_transition(root: Path, relative_source: Path) -> tuple[str, str]:
    text = (root / relative_source).read_text(encoding="utf-8")
    date_match = DATE_FIELD.search(text)
    if not date_match:
        raise ValueError(f"{relative_source}: missing frontmatter date")
    status_match = STATUS_FIELD.search(text)
    if not status_match:
        raise ValueError(f"{relative_source}: missing frontmatter status")
    return status_match.group(1), date_match.group(1)


def expected_transition(status: str, date: str) -> str:
    return f"**Transitioned to `{status}` on**: {date}"


def validate_tracked_report(
    text: str,
    *,
    relative_report: Path,
    relative_source: Path,
    transition_status: str,
    transition_date: str,
) -> str:
    match = DOCUMENT_LINE.search(text)
    if not match:
        raise ValueError(f"{relative_report}: missing Document identity")
    actual_source = match.group(1)
    expected_source = relative_source.as_posix()
    if Path(actual_source).is_absolute():
        raise ValueError(f"{relative_report}: absolute host path: {actual_source}")
    if actual_source != expected_source:
        raise ValueError(
            f"{relative_report}: Document identity {actual_source!r} != {expected_source!r}"
        )
    transition_match = TRANSITION_LINE.search(text)
    if not transition_match:
        raise ValueError(f"{relative_report}: missing terminal transition identity")
    actual_transition = transition_match.group(0)
    canonical_transition = expected_transition(transition_status, transition_date)
    if actual_transition != canonical_transition:
        raise ValueError(
            f"{relative_report}: transition identity {actual_transition!r} "
            f"!= {canonical_transition!r}"
        )
    if not GENERATED_LINE.search(text):
        raise ValueError(f"{relative_report}: missing Generated timestamp")
    return text


def canonicalize_generated_report(
    text: str,
    *,
    relative_report: Path,
    relative_source: Path,
    transition_status: str,
    transition_date: str,
) -> str:
    if not DOCUMENT_LINE.search(text):
        raise ValueError(f"{relative_report}: missing Document identity")
    portable = DOCUMENT_LINE.sub(
        f"**Document**: `{relative_source.as_posix()}`", text, count=1
    )
    if not TRANSITION_LINE.search(portable):
        raise ValueError(f"{relative_report}: missing terminal transition identity")
    portable = TRANSITION_LINE.sub(
        expected_transition(transition_status, transition_date), portable, count=1
    )
    if not GENERATED_LINE.search(portable):
        raise ValueError(f"{relative_report}: missing Generated timestamp")
    return portable


def comparison_bytes(text: str) -> bytes:
    return GENERATED_LINE.sub(VOLATILE_GENERATED, text, count=1).encode("utf-8")


def run_decree(root: Path, report_paths: tuple[Path, ...]) -> None:
    doc_ids = [path.stem for path in report_paths]
    result = subprocess.run(
        ["uv", "run", "decree", "report", "regenerate", *doc_ids, "--project", str(root)],
        cwd=root,
        text=True,
        capture_output=True,
    )
    if result.returncode:
        detail = (result.stderr or result.stdout).strip()
        raise ValueError(f"Decree report regeneration failed: {detail}")


def canonicalize_written_reports(root: Path, report_paths: tuple[Path, ...]) -> None:
    for relative_report in report_paths:
        relative_source = source_for_report(root, relative_report)
        transition_status, transition_date = source_transition(root, relative_source)
        report = root / relative_report
        canonical = canonicalize_generated_report(
            report.read_text(encoding="utf-8"),
            relative_report=relative_report,
            relative_source=relative_source,
            transition_status=transition_status,
            transition_date=transition_date,
        )
        report.write_text(canonical, encoding="utf-8")


def actual_report_paths(root: Path) -> tuple[Path, ...]:
    return tuple(
        sorted(path.relative_to(root) for path in (root / "decree").glob("*/reports/*.md"))
    )


def check_report_set(root: Path, expected: tuple[Path, ...]) -> list[str]:
    failures = []
    expected_set = set(expected)
    actual_set = set(actual_report_paths(root))
    for path in sorted(expected_set - actual_set):
        failures.append(f"missing expected report: {path}")
    for path in sorted(actual_set - expected_set):
        failures.append(f"extra report: {path}")
    return failures


def populate_isolated_expected_reports(
    root: Path, report_paths: tuple[Path, ...], temporary: Path
) -> None:
    shutil.copy2(root / "decree.toml", temporary / "decree.toml")
    shutil.copytree(root / "decree", temporary / "decree")
    for reports_dir in (temporary / "decree").glob("*/reports"):
        shutil.rmtree(reports_dir)
    run_decree(temporary, report_paths)
    canonicalize_written_reports(temporary, report_paths)


def check_reports(root: Path, report_paths: tuple[Path, ...]) -> int:
    failures = check_report_set(root, report_paths)
    if failures:
        for failure in failures:
            print(f"decree-report: {failure}", file=sys.stderr)
        return 1

    try:
        with tempfile.TemporaryDirectory(
            prefix="recon-decree-report-check.", ignore_cleanup_errors=True
        ) as temporary_name:
            temporary = Path(temporary_name)
            populate_isolated_expected_reports(root, report_paths, temporary)
            for relative_report in report_paths:
                relative_source = source_for_report(root, relative_report)
                transition_status, transition_date = source_transition(
                    root, relative_source
                )
                actual = validate_tracked_report(
                    (root / relative_report).read_text(encoding="utf-8"),
                    relative_report=relative_report,
                    relative_source=relative_source,
                    transition_status=transition_status,
                    transition_date=transition_date,
                )
                expected = (temporary / relative_report).read_text(encoding="utf-8")
                if comparison_bytes(actual) != comparison_bytes(expected):
                    failures.append(f"{relative_report}: complete report content drift")
    except (OSError, UnicodeError, ValueError, subprocess.SubprocessError) as exc:
        failures.append(str(exc))

    if failures:
        for failure in failures:
            print(f"decree-report: {failure}", file=sys.stderr)
        return 1
    print(
        "decree reports: clean — complete regenerated content agrees "
        f"for {len(report_paths)} report(s) (Generated timestamp ignored)"
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--root", type=Path, default=Path.cwd(), help=argparse.SUPPRESS)
    args = parser.parse_args()
    root = args.root.resolve()
    try:
        report_paths = tracked_report_paths(root)
        if not report_paths:
            raise ValueError("no tracked Decree completion reports")
        if args.check:
            return check_reports(root, report_paths)
        run_decree(root, report_paths)
        canonicalize_written_reports(root, report_paths)
        print(f"decree reports: regenerated — {len(report_paths)} complete report(s)")
        return 0
    except (OSError, UnicodeError, ValueError, subprocess.SubprocessError) as exc:
        print(f"decree-report: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
