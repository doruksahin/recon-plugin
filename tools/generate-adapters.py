#!/usr/bin/env python3
"""Generate Codex plugin and skill UI metadata from canonical Recon sources."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CLAUDE_MANIFEST = ROOT / "recon/.claude-plugin/plugin.json"
CODEX_MANIFEST = ROOT / "recon/.codex-plugin/plugin.json"
CODEX_MARKETPLACE = ROOT / ".agents/plugins/marketplace.json"
MAX_DESCRIPTION_CHARS = 200
INTERNAL_SKILL_TRIGGERS = {"recon-decree": "Invoked by"}
USER_FACING_TRIGGER = "Use when"

INTERFACE = {
    "recon-triage": (
        "Recon Triage",
        "Evidence-first Jira blocker triage",
        "Use $recon-triage to assess whether this Jira ticket is ready or blocked.",
    ),
    "recon-discovery": (
        "Recon Discovery",
        "Map code, behavior, routing, and handoff",
        "Use $recon-discovery to prepare this READY ticket for an approval gate.",
    ),
    "recon-repro": (
        "Recon Repro",
        "Capture honest UI reproduction evidence",
        "Use $recon-repro to reproduce this visible behavior and capture evidence.",
    ),
    "recon-report": (
        "Recon Report",
        "Render a self-contained Recon dossier",
        "Use $recon-report to render the current ticket's Recon dossier.",
    ),
    "recon-decree": (
        "Recon Decree",
        "Internal Decree continuation for Discovery",
        "Continue the active Recon Discovery run through Decree governance using its existing artifacts.",
    ),
    "recon-help": (
        "Recon Help",
        "Check setup and explain the Recon workflow",
        "Use $recon-help to check this Recon installation and show the next command.",
    ),
    "recon-publish": (
        "Recon Publish",
        "Release and distribute Recon safely",
        "Use $recon-publish to preview and gate a Recon release.",
    ),
    "recon-state": (
        "Recon State",
        "Render the living ticket state canvas",
        "Use $recon-state to render the current state of this Recon ticket.",
    ),
}


def frontmatter(skill_file: Path) -> dict[str, str]:
    lines = skill_file.read_text().splitlines()
    if not lines or lines[0] != "---":
        raise ValueError(f"{skill_file}: missing YAML frontmatter")
    data: dict[str, str] = {}
    for line in lines[1:]:
        if line == "---":
            break
        if ":" in line:
            key, value = line.split(":", 1)
            data[key.strip()] = value.strip().strip('"')
    return data


def yaml_quote(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def validate_descriptions(skills: list[tuple[str, Path, dict[str, str]]]) -> None:
    seen: dict[str, str] = {}
    errors: list[str] = []
    for name, skill_dir, metadata in skills:
        description = metadata.get("description", "").strip()
        source = f"{skill_dir}/SKILL.md"
        if not description:
            errors.append(f"{source}: description must not be empty")
            continue

        previous = seen.get(description)
        if previous:
            errors.append(
                f"{source}: description duplicates {previous}/SKILL.md"
            )
        else:
            seen[description] = str(skill_dir)

        length = len(description)
        if length > MAX_DESCRIPTION_CHARS:
            errors.append(
                f"{source}: description is {length} Unicode characters; "
                f"maximum is {MAX_DESCRIPTION_CHARS}"
            )

        trigger = INTERNAL_SKILL_TRIGGERS.get(name, USER_FACING_TRIGGER)
        if trigger not in description:
            errors.append(
                f"{source}: description must include the trigger cue {trigger!r}"
            )

    if errors:
        raise ValueError("invalid skill descriptions:\n- " + "\n- ".join(errors))


def expected_outputs() -> dict[Path, str]:
    manifest = json.loads(CLAUDE_MANIFEST.read_text())
    skills: list[tuple[str, Path, dict[str, str]]] = []
    for raw_path in manifest.get("skills", []):
        skill_dir = (CLAUDE_MANIFEST.parent.parent / raw_path).resolve()
        metadata = frontmatter(skill_dir / "SKILL.md")
        name = metadata.get("name", "")
        if name != skill_dir.name:
            raise ValueError(
                f"{skill_dir}/SKILL.md: name {name!r} must match folder {skill_dir.name!r}"
            )
        if name not in INTERFACE:
            raise ValueError(f"{name}: missing generated interface metadata")
        skills.append((name, skill_dir, metadata))

    validate_descriptions(skills)

    codex = {
        "name": manifest["name"],
        "version": manifest["version"],
        "description": manifest["description"],
        "author": manifest["author"],
        "keywords": manifest.get("keywords", []),
        "skills": "./skills/",
        "interface": {
            "displayName": "Recon",
            "shortDescription": "Evidence-first Jira ticket reconnaissance",
            "longDescription": manifest["description"],
            "developerName": manifest["author"]["name"],
            "category": "Productivity",
            "capabilities": ["Read", "Write", "Interactive"],
            "defaultPrompt": [
                "Triage this Jira ticket before planning.",
                "Prepare this READY ticket for implementation.",
                "Show the current Recon state for this ticket.",
            ],
        },
    }
    marketplace = {
        "name": "recon-plugin",
        "interface": {"displayName": "Recon Plugin"},
        "plugins": [
            {
                "name": manifest["name"],
                "source": {"source": "local", "path": "./recon"},
                "policy": {
                    "installation": "AVAILABLE",
                    "authentication": "ON_INSTALL",
                },
                "category": "Productivity",
            }
        ],
    }
    outputs = {
        CODEX_MANIFEST: json.dumps(codex, indent=2, ensure_ascii=False) + "\n",
        CODEX_MARKETPLACE: json.dumps(marketplace, indent=2, ensure_ascii=False) + "\n",
    }

    for name, skill_dir, _metadata in skills:
        display_name, short_description, default_prompt = INTERFACE[name]
        body = (
            "interface:\n"
            f"  display_name: {yaml_quote(display_name)}\n"
            f"  short_description: {yaml_quote(short_description)}\n"
            f"  default_prompt: {yaml_quote(default_prompt)}\n"
        )
        outputs[skill_dir / "agents/openai.yaml"] = body
    return outputs


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail if generated files drift")
    args = parser.parse_args()
    try:
        outputs = expected_outputs()
    except (KeyError, OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"adapter generation failed: {exc}", file=sys.stderr)
        return 2

    drift: list[str] = []
    for target, expected in outputs.items():
        if args.check:
            actual = target.read_text() if target.exists() else None
            if actual != expected:
                drift.append(str(target.relative_to(ROOT)))
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(expected)
            print(f"generated: {target.relative_to(ROOT)}")

    if drift:
        for target in drift:
            print(f"DRIFT: {target}")
        print("run: python3 tools/generate-adapters.py", file=sys.stderr)
        return 1
    if args.check:
        print(f"adapters: clean — {len(outputs)} generated file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
