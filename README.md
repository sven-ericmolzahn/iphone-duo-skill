# iPhone Duo adaptation — an agent skill

A skill that teaches coding agents — **Claude Code, OpenAI Codex, Cursor, Gemini CLI, Copilot** and anything else that reads [Agent Skills](https://agentskills.io) — how to adapt an iOS app for **iPhone Duo**, Apple's folding iPhone: two displays, a hinge, toolbars and tab bars that move to the side, and the iOS 27.1 layout APIs (`ArrangementView`, reserved regions, the hinge API, vertical-bar controls).

It exists because two days with the 27.1 SDK went like this:

- A blog said `ArrangementView` "isn't in the SDK yet". It is — declared in `SwiftUICore`, where nobody greps.
- A layout preference set on the arrangement compiled, did nothing, and left the split at 50/50. It belongs on the *pane*.
- Half-folded, one pane collapsed to 145 points with text stacked one character per line. It needed its own `minWidth`.
- A video summary had the tab-bar compression enum backwards. Apple's prose says `.divisions`; the SDK says `.division`.
- A camera API from a Tech Talk isn't in the shipping headers at all.

None of that is in a model's training data, and half of what *is* on the web is wrong. So this skill is built differently.

## What makes it trustworthy

- **Read from the SDK, not from the internet.** Every API name, enum case, module and availability in `references/api-reference.md` came out of the `.swiftinterface` files and headers of Xcode 27.1.
- **Every code sample compiles.** `tests/typecheck.sh` type-checks all of them against the installed SDK — under both default actor isolations, because a sample that builds in isolation and fails in a modern project is worthless.
- **Numbers are measurements.** Display sizes, safe-area insets per pose, the 40-point hinge band, the 84-point vertical bar, what an arrangement does when folded — logged from a running app on the iPhone Duo simulator, with the tool that ships in the skill.
- **It says what it doesn't know.** Announced-but-missing APIs are marked as such. A modifier that turned out to be a no-op in an A/B test is documented as a no-op.
- **It stays current.** `scripts/check-sdk.sh` re-verifies the API surface against *your* Xcode in two seconds.

Verified against **Xcode 27.1 (27A9269), iOS 27.1 SDK and simulator runtime (24A94401)** on 2026-09-19.

## Does it help? A measured answer

Three realistic tasks ([`evals/evals.json`](evals/evals.json)), each given to the same model twice — once with this skill, once without — under identical rules (compiler and web search allowed, no simulators). Graded by [`evals/grade.py`](evals/grade.py): objective checks only, the first of which is *does the Swift type-check against the real iOS 27.1 SDK*.

| Task | With skill | Without |
|---|---|---|
| Turn an `HStack` into a fold-safe two-pane layout | **11 / 11** | 7 / 11 |
| Fix a toolbar for the vertical bar | **8 / 8** | 2 / 8 |
| Audit a file and write up what will break | **13 / 14** | 10 / 14 |
| **Pass rate** | **98 %** | 53 % |
| Mean time per task | **4 min 46 s** | 9 min 58 s |
| Mean tokens per task | **135 k** | 156 k |

What the numbers hide is more interesting than the numbers. Without the skill the model was *resourceful* — it found `ArrangementView` by reading the SDK's interface files itself — and its code **compiled**. It was still wrong: it passed `330` (points) where a *ratio* was expected, gave the second pane no minimum, and switched layout on every iPhone running iOS 27.1. That is precisely the half-folded "sliver" bug the task asked it to fix. For the toolbar it didn't find the platform APIs at all and engineered around the device instead, hiding buttons until the system stopped overflowing. **The spellings are discoverable; the traps are not.** That is what this skill is for.

Honest limits: one run per cell (no variance estimate), one model (Claude Sonnet 5), simulator not hardware, and the grader was revised once after reading the outputs — two fixes that *helped* the answers it had wrongly failed, and two new objective checks applied to both arms. Raw results: [`evals/results/`](evals/results). Reproduce it with your own agent and send a PR.

## Install

The skill is the folder [`skills/iphone-duo-adaptation/`](skills/iphone-duo-adaptation). Copy or symlink it to where your agent looks:

| Agent | Personal (all projects) | Per project |
|---|---|---|
| **Claude Code** | `~/.claude/skills/iphone-duo-adaptation/` | `.claude/skills/iphone-duo-adaptation/` |
| **OpenAI Codex** | `~/.agents/skills/iphone-duo-adaptation/` | `.agents/skills/iphone-duo-adaptation/` |
| **Other Agent Skills clients** (Cursor, Gemini CLI, Copilot, …) | see the client's docs — the folder is spec-compliant and needs no changes | |

```bash
git clone https://github.com/sven-ericmolzahn/iphone-duo-skill.git
mkdir -p ~/.claude/skills && ln -s "$PWD/iphone-duo-skill/skills/iphone-duo-adaptation" ~/.claude/skills/
```

```bash
mkdir -p ~/.agents/skills && ln -s "$PWD/iphone-duo-skill/skills/iphone-duo-adaptation" ~/.agents/skills/
```

**Agents without skill support.** Add one line to `AGENTS.md` (or your tool's rules file) and keep the folder in the repository:

```markdown
When working on iPhone Duo, foldable-iPhone layout, vertical toolbars or ArrangementView,
first read skills/iphone-duo-adaptation/SKILL.md and follow it.
```

Then just ask: *"Audit this app for iPhone Duo"*, *"Why is my layout squeezed when the phone is half folded?"*, *"Move this HStack to an ArrangementView"*. In Codex you can also invoke it explicitly with `$iphone-duo-adaptation`.

## What's inside

```
skills/iphone-duo-adaptation/
├── SKILL.md                      the model, the workflow, the traps — ~200 lines
├── references/                   loaded only when the task needs them
│   ├── api-reference.md          SwiftUI · UIKit · AVFoundation, exact spellings
│   ├── arrangement-views.md      split / overlay, pane sizing, measured behaviour
│   ├── vertical-bars.md          toolbars, tab bars, sheets at the side
│   ├── reserved-regions-and-hinge.md
│   ├── camera-and-scenes.md
│   ├── device-and-metrics.md     sizes, insets, regions per pose
│   ├── audit-checklist.md        what to fix first, and what grep can't see
│   └── simulator-and-verification.md
├── scripts/
│   ├── check-sdk.sh              which Duo APIs does YOUR Xcode ship, and in which module?
│   ├── audit.sh                  ranked reading list of likely breakage in a project
│   └── capture-displays.sh       screenshot BOTH displays (the default grabs the dark one)
├── assets/
│   └── DuoLayoutProbe.swift      drop-in DEBUG probe: size, insets, regions, hinge → log
└── agents/openai.yaml            optional Codex UI metadata
tests/                            type-checks every sample; validates the skill format
evals/                            prompts for measuring the skill against a no-skill baseline
```

The scripts are useful on their own, without any agent:

```bash
skills/iphone-duo-adaptation/scripts/check-sdk.sh
```

```bash
skills/iphone-duo-adaptation/scripts/audit.sh path/to/YourApp
```

## Keeping it honest

These APIs shipped as beta. After every Xcode update:

```bash
tests/typecheck.sh && python3 tests/validate-skill.py && skills/iphone-duo-adaptation/scripts/check-sdk.sh
```

If something fails, the SDK is right and the skill is wrong — fix the sample, then the prose. Pull requests that add *measured* facts (hardware numbers instead of simulator numbers, the outer display in landscape, Split View insets) are especially welcome; please say how you measured.

## Not affiliated with Apple

An independent, community resource. iPhone, iOS, Xcode, SwiftUI and UIKit are trademarks of Apple Inc. It reproduces API names and measured facts, not Apple's documentation — read [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo), [Preparing your app for iPhone Duo](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo) and Tech Talks 111461–111466 for the source material.

## License

MIT — see [LICENSE](LICENSE).
