#!/usr/bin/env python3
"""Grades eval runs for the iphone-duo-adaptation skill.

Objective checks only — above all: does the Swift an agent produced actually
type-check against the installed iOS SDK? Writes grading.json files in the
layout the skill-creator benchmark tooling expects:

    <iteration>/eval-<id>-<name>/<config>/run-1/{outputs/, grading.json}

Usage: evals/grade.py <iteration-dir>
       (expects <iteration-dir>/<eval-name>/<config>/outputs/ from the runs)
"""
import json, pathlib, re, shutil, subprocess, sys

ITER = pathlib.Path(sys.argv[1]).expanduser().resolve()
REPO = pathlib.Path(__file__).resolve().parent.parent
EVALS = {e["name"]: e for e in json.load(open(REPO / "evals/evals.json"))["evals"]}
SDK = subprocess.run(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"],
                     capture_output=True, text=True).stdout.strip()


def typecheck(path):
    """(ok, evidence) — type-check one Swift file at an iOS 26 deployment target."""
    if not SDK:
        return False, "no iOS simulator SDK available to the grader"
    r = subprocess.run(["swiftc", "-typecheck", "-sdk", SDK, "-target",
                        "arm64-apple-ios26.0-simulator", str(path)],
                       capture_output=True, text=True)
    if r.returncode == 0:
        return True, "swiftc -typecheck succeeded against " + pathlib.Path(SDK).name
    errors = [l.split("error:", 1)[1].strip() for l in r.stderr.splitlines() if "error:" in l]
    unique = list(dict.fromkeys(errors))
    return False, f"{len(errors)} compile error(s): " + " | ".join(unique[:4])


def code_only(text):
    """Source with comments removed, so a word in prose never counts as code."""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return "\n".join(re.sub(r"//.*$", "", line) for line in text.splitlines())


def has(text, pattern, flags=re.I):
    m = re.search(pattern, text, flags)
    return bool(m), (f"found “{m.group(0)[:60]}”" if m else f"no match for /{pattern}/")


def find_output(outputs, suffix):
    files = sorted(outputs.rglob(f"*{suffix}"))
    return files[0] if files else None


def grade_arrangement(outputs):
    f = find_output(outputs, ".swift")
    if not f:
        return [("Wrote a Swift file", False, "no .swift file in outputs/")]
    t = code_only(f.read_text())
    out = [("Wrote a Swift file", True, f.name)]
    out.append(("Compiles against the iOS 27.1 SDK at an iOS 26 deployment target", *typecheck(f)))
    out.append(("Uses ArrangementView", *has(t, r"\bArrangementView\s*[{(]", 0)))
    out.append(("New API is availability-gated for iOS 27.1", *has(t, r"[#@]available\(\s*iOS 27\.1", 0)))
    calls = len(re.findall(r"\.splitArrangementLayout(Size|Ratio)\(|\.splitArrangementFixedLayoutSize\(", t))
    out.append(("Each pane states its own size preference (≥ 2 pane-level calls)", calls >= 2,
                f"{calls} splitArrangement… call(s)"))
    floors = len(re.findall(r"\bmin(Width|Horizontal)\s*:", t))
    out.append(("The secondary pane has a floor too (≥ 2 minimums)", floors >= 2, f"{floors} minimum(s) declared"))
    # A preference chained at the same indentation as .arrangementViewStyle sits on the container.
    on_container, lines = False, t.splitlines()
    for i, line in enumerate(lines):
        if ".arrangementViewStyle(" in line:
            indent = len(line) - len(line.lstrip())
            near = lines[max(0, i - 3): i + 4]
            on_container |= any(".splitArrangement" in n and len(n) - len(n.lstrip()) == indent for n in near)
    out.append(("No size preference on the ArrangementView itself (it is ignored there)", not on_container,
                "preference chained on the container" if on_container else "none on the container"))
    # Navigation must wrap the arrangement, never sit inside one of its panes.
    arr = re.search(r"\bArrangementView\s*\{", t)
    inside = False
    if arr:
        depth, i = 0, arr.end() - 1
        start = i
        while i < len(t):                      # walk to the end of `} secondary: { … }`
            depth += t[i] == "{"; depth -= t[i] == "}"
            if depth == 0 and not re.match(r"\s*secondary\s*:", t[i + 1:]):
                break
            i += 1
        inside = "NavigationStack" in t[start:i] or "NavigationSplitView" in t[start:i]
    out.append(("Navigation stays outside the arrangement", bool(arr) and "NavigationStack" in t and not inside,
                "navigation container inside a pane" if inside else "NavigationStack wraps the arrangement"))
    # The task said: behave the same on a normal iPhone. An OS check alone can't promise
    # that — iOS 27.1 runs on ordinary iPhones too. The container has to decide.
    by_container = re.search(r"horizontalSizeClass|verticalSizeClass|onGeometryChange|GeometryReader|containerRelativeFrame", t)
    out.append(("Enters the arrangement based on the container (size class / geometry), not the OS version alone",
                bool(by_container), f"uses {by_container.group(0)}" if by_container else "only #available decides — every iPhone on iOS 27.1 changes layout"))
    # A ratio is 0…1. Points passed as a ratio compile and are wrong.
    consts = {m.group(1): float(m.group(2)) for m in re.finditer(r"\blet\s+(\w+)\s*(?::\s*\w+)?\s*=\s*([0-9.]+)", t)}
    bad = []
    for call in re.findall(r"\.splitArrangementLayoutRatio\(([^)]*)\)", t):
        for arg in re.findall(r"(?:Self\.|self\.)?([A-Za-z_]\w*|[0-9.]+)\s*(?=[,)]|$)", call.split(":")[-1] if ":" not in call else " ".join(x.split(":")[-1] for x in call.split(","))):
            value = float(arg) if re.fullmatch(r"[0-9.]+", arg) else consts.get(arg)
            if value is not None and value > 1:
                bad.append(f"{arg}={value:g}")
    out.append(("Ratios are ratios (0…1), not point values", not bad, "ratio given as " + ", ".join(bad) if bad else "ok / none used"))
    out.append(("Keeps a fallback layout for older systems / unsuitable containers",
                bool(re.search(r"\belse\b", t)) and bool(re.search(r"\b(HStack|VStack|ScrollView|ViewThatFits)\b", t)),
                "else-branch with a classic layout" if re.search(r"\belse\b", t) else "no else branch"))
    return out


def grade_toolbar(outputs):
    f = find_output(outputs, ".swift")
    if not f:
        return [("Wrote a Swift file", False, "no .swift file in outputs/")]
    t = code_only(f.read_text())
    out = [("Wrote a Swift file", True, f.name)]
    out.append(("Compiles against the iOS 27.1 SDK at an iOS 26 deployment target", *typecheck(f)))
    out.append(("Keeps Compose visible with visibilityPriority(.high)", *has(t, r"\.visibilityPriority\(\s*\.high", 0)))
    out.append(("Moves the custom menu into the system overflow (ToolbarOverflowMenu)", *has(t, r"\bToolbarOverflowMenu\b", 0)))
    # A hand-made ellipsis menu is fine in the fallback for systems that have no
    # ToolbarOverflowMenu; beside the system's overflow it is the reported bug.
    gate = re.search(r"#available\(\s*iOS 27[^)]*\)", t)
    modern = t
    if gate:
        tail = t[gate.end():]
        split = re.search(r"\}\s*else\s*\{", tail)
        modern = tail[:split.start()] if split else tail
    leftover = re.search(r'"ellipsis', modern) or (not gate and re.search(r'"ellipsis', t))
    out.append(("No hand-made ellipsis menu on iOS 27 (the ellipsis is reserved for the system overflow)", not leftover,
                "hand-made ellipsis menu still present on the iOS 27 path" if leftover else "none on the iOS 27 path"))
    out.append(("Keeps the Select/Done text item horizontal (axisBehavior(.horizontalOnly))",
                *has(t, r"\.axisBehavior\(\s*\.horizontalOnly", 0)))
    labelled = len(re.findall(r"systemImage\s*:", t)) + len(re.findall(r"\bLabel\(", t))
    out.append(("Toolbar items carry a title AND a symbol (≥ 4)", labelled >= 4, f"{labelled} titled-symbol item(s)"))
    out.append(("New API is availability-gated", *has(t, r"[#@]available\(\s*iOS 27", 0)))
    return out


def grade_audit(outputs):
    f = find_output(outputs, ".md")
    if not f:
        return [("Wrote a Markdown report", False, "no .md file in outputs/")]
    t = f.read_text()
    checks = [
        ("Flags UIScreen.main (two screens / deprecated)", r"UIScreen\.main"),
        ("Flags layout by device idiom", r"idiom"),
        ("Says the inner display is regular width on a phone", r"regular[- ]width|regular (horizontal )?size class|horizontalSizeClass"),
        ("Flags the hard-coded 47-point inset fallback", r"\b47\b"),
        ("Flags symmetric inset arithmetic / asymmetric safe areas", r"asymmetr|\*\s*2|twice|both sides|symmetric"),
        ("Flags connectedScenes.first / multiple scenes", r"connectedScenes|multiple (scenes|windows)|several scenes"),
        ("Flags the hero sized as 60 % of screen height", r"0\.6|60\s?%"),
        ("Flags the stretched search field / no readable measure", r"maxWidth|stretch|readable|search ?field"),
        ("Flags idiom-driven grid columns", r"column"),
        ("Knows bars move to the side (vertical bar)", r"vertical bar|bars? (move|sit|are) (to|at|on) the side|side of the (screen|display)"),
        ("Flags the fixed camera pick / folding is not a scene-phase change", r"scenePhase|scene[- ]phase|DiscoverySession|discovery session|between displays|opens? (and|or) closes?"),
        ("Flags the uncatchable flash-mode crash", r"supportedFlashModes"),
    ]
    out = [("Wrote a Markdown report", True, f.name)]
    out += [(name, *has(t, pattern)) for name, pattern in checks]
    # Wrong spellings that circulate in blog posts; a report citing them teaches them.
    wrong = re.findall(r"\.divisions\b|\.occlusions\b|\.arrangementStyle\(|UIFoldingState|isFolded\b|FoldableView", t)
    out.append(("Cites no invented or misspelled Duo APIs", not wrong, f"found {sorted(set(wrong))}" if wrong else "none found"))
    return out


GRADERS = {"hstack-to-arrangement": grade_arrangement,
           "toolbar-vertical-bar": grade_toolbar,
           "audit-report": grade_audit}

for name, grader in GRADERS.items():
    ev = EVALS[name]
    for config in ("with_skill", "without_skill"):
        src = ITER / name / config / "outputs"
        if not src.exists():
            continue
        run = ITER / f"eval-{ev['id']}-{name}" / config / "run-1"
        if (run / "outputs").exists():
            shutil.rmtree(run / "outputs")
        shutil.copytree(src, run / "outputs")
        results = grader(run / "outputs")
        passed = sum(1 for _, ok, _ in results if ok)
        grading = {"expectations": [{"text": text, "passed": bool(ok), "evidence": ev_} for text, ok, ev_ in results],
                   "summary": {"passed": passed, "failed": len(results) - passed, "total": len(results),
                               "pass_rate": round(passed / len(results), 2)}}
        timing = ITER / name / config / "timing.json"
        if timing.exists():
            # Sibling file only: the benchmark aggregator reads tokens from
            # timing.json, and skips it when grading.json carries a duration.
            shutil.copy(timing, run / "timing.json")
        (run / "grading.json").write_text(json.dumps(grading, indent=2, ensure_ascii=False))
        meta = ITER / f"eval-{ev['id']}-{name}" / "eval_metadata.json"
        meta.write_text(json.dumps({"eval_id": ev["id"], "eval_name": name, "prompt": ev["prompt"],
                                    "assertions": [text for text, _, _ in results]}, indent=2, ensure_ascii=False))
        print(f"{name:26s} {config:14s} {passed}/{len(results)}")
        for text, ok, ev_ in results:
            if not ok:
                print(f"    ✗ {text} — {ev_}")
