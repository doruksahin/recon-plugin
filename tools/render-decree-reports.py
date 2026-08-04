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
    r"^(\*\*Transitioned to `[^`]+` on\*\*: )\d{4}-\d{2}-\d{2}$", re.MULTILINE
)
DATE_FIELD = re.compile(r"^date:\s*['\"]?([^'\"\s]+)['\"]?\s*$", re.MULTILINE)
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


def source_date(root: Path, relative_source: Path) -> str:
    text = (root / relative_source).read_text(encoding="utf-8")
    match = DATE_FIELD.search(text)
    if not match:
        raise ValueError(f"{relative_source}: missing frontmatter date")
    return match.group(1)


def canonicalize_report(
    text: str,
    *,
    relative_report: Path,
    relative_source: Path,
    transition_date: str,
    validate_document: bool,
) -> str:
    match = DOCUMENT_LINE.search(text)
    if not match:
        raise ValueError(f"{relative_report}: missing Document identity")
    actual_source = match.group(1)
    expected_source = relative_source.as_posix()
    if validate_document:
        if Path(actual_source).is_absolute():
            raise ValueError(f"{relative_report}: absolute host path: {actual_source}")
        if actual_source != expected_source:
            raise ValueError(
                f"{relative_report}: Document identity {actual_source!r} != {expected_source!r}"
            )
    portable = DOCUMENT_LINE.sub(f"**Document**: `{expected_source}`", text, count=1)
    if not TRANSITION_LINE.search(portable):
        raise ValueError(f"{relative_report}: missing terminal transition identity")
    portable = TRANSITION_LINE.sub(rf"\g<1>{transition_date}", portable, count=1)
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
        report = root / relative_report
        canonical = canonicalize_report(
            report.read_text(encoding="utf-8"),
            relative_report=relative_report,
            relative_source=relative_source,
            transition_date=source_date(root, relative_source),
            validate_document=False,
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


def isolated_expected_reports(root: Path, report_paths: tuple[Path, ...]) -> Path:
    temporary = Path(tempfile.mkdtemp(prefix="recon-decree-report-check."))
    shutil.copy2(root / "decree.toml", temporary / "decree.toml")
    shutil.copytree(root / "decree", temporary / "decree")
    for reports_dir in (temporary / "decree").glob("*/reports"):
        shutil.rmtree(reports_dir)
    run_decree(temporary, report_paths)
    canonicalize_written_reports(temporary, report_paths)
    return temporary


def check_reports(root: Path, report_paths: tuple[Path, ...]) -> int:
    failures = check_report_set(root, report_paths)
    if failures:
        for failure in failures:
            print(f"decree-report: {failure}", file=sys.stderr)
        return 1

    temporary = None
    try:
        temporary = isolated_expected_reports(root, report_paths)
        for relative_report in report_paths:
            relative_source = source_for_report(root, relative_report)
            actual = canonicalize_report(
                (root / relative_report).read_text(encoding="utf-8"),
                relative_report=relative_report,
                relative_source=relative_source,
                transition_date=source_date(root, relative_source),
                validate_document=True,
            )
            expected = (temporary / relative_report).read_text(encoding="utf-8")
            if comparison_bytes(actual) != comparison_bytes(expected):
                failures.append(f"{relative_report}: complete report content drift")
    except (OSError, UnicodeError, ValueError, subprocess.SubprocessError) as exc:
        failures.append(str(exc))
    finally:
        if temporary is not None:
            shutil.rmtree(temporary, ignore_errors=True)

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
