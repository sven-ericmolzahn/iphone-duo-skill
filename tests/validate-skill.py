#!/usr/bin/env python3
"""Checks the skill against the Agent Skills specification (agentskills.io).

Deliberately dependency-free. For the reference validator see
https://github.com/agentskills/agentskills/tree/main/skills-ref
"""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
errors, notes = [], []

for skill_md in sorted((ROOT / "skills").glob("*/SKILL.md")):
    skill_dir = skill_md.parent
    text = skill_md.read_text()
    match = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
    if not match:
        errors.append(f"{skill_md}: no YAML frontmatter"); continue
    front, body = match.groups()

    name = re.search(r"^name:\s*(.+)$", front, re.M)
    name = name.group(1).strip().strip('"') if name else ""
    if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", name) or len(name) > 64:
        errors.append(f"{skill_md}: invalid name '{name}'")
    if name != skill_dir.name:
        errors.append(f"{skill_md}: name '{name}' must match directory '{skill_dir.name}'")

    # Either a plain scalar on one line, or a block scalar (>-, >, |) whose
    # indented lines run until the next top-level key.
    block = re.search(r"^description:[ \t]*[>|][+-]?[ \t]*\n((?:[ \t]+.*\n?)+)", front, re.M)
    plain = re.search(r"^description:[ \t]*(?![>|])(.+)$", front, re.M)
    raw = block.group(1) if block else (plain.group(1) if plain else "")
    description = " ".join(l.strip() for l in raw.splitlines()).strip().strip('"')
    if not 1 <= len(description) <= 1024:
        errors.append(f"{skill_md}: description is {len(description)} chars (1–1024 allowed)")

    compat = re.search(r"^compatibility:\s*(.+)$", front, re.M)
    if compat and len(compat.group(1)) > 500:
        errors.append(f"{skill_md}: compatibility exceeds 500 chars")

    lines = text.count("\n") + 1
    if lines > 500:
        errors.append(f"{skill_md}: {lines} lines (keep under 500)")

    # Every relative file the skill points at must exist.
    for ref in sorted(set(re.findall(r"`((?:references|scripts|assets|agents)/[A-Za-z0-9_.\-/]+)`", text))):
        if not (skill_dir / ref).exists():
            errors.append(f"{skill_md}: references missing file {ref}")
    for ref_file in sorted((skill_dir / "references").glob("*.md")):
        if f"references/{ref_file.name}" not in text:
            errors.append(f"{ref_file.name}: not mentioned in SKILL.md — agents will never find it")
        # In-page anchors in a table of contents must resolve.
        content = ref_file.read_text()
        heads = {re.sub(r"[^a-z0-9 \-]", "", h.lower()).strip().replace(" ", "-")
                 for h in re.findall(r"^#+\s+(.+)$", content, re.M)}
        for anchor in re.findall(r"\]\(#([^)]+)\)", content):
            if anchor not in heads:
                errors.append(f"{ref_file.name}: broken anchor #{anchor}")

    notes.append(f"{name}: {lines} lines, description {len(description)} chars, "
                 f"~{len(body.split())} words in the body")

for note in notes: print("ok  ", note)
for error in errors: print("FAIL", error)
sys.exit(1 if errors else 0)
