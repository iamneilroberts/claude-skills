---
name: review-panel
description: Run multiple independent code reviewers (Codex + Gemini + a fresh Claude) on the current diff or a plan, merge their structured verdicts, and apply a consensus-gated challenge round — returning a pass/fail exit code. Use for "panel review this", "get a multi-model review before I ship", "second-opinion review this diff", or /review-panel. Complements single-reviewer /codex-review.
---

# review-panel

Delegate entirely to `review-panel.sh` — do not hand-run the reviewers or re-judge their verdicts.

## Invocation
`/review-panel [--base <ref> | --staged | --plan <file>] [--reviewers codex,gemini,claude] [--block-at 0-3] [--focus "…" | --focus-file <f>] [--strict] [--out <path>]`

## Rules (non-negotiable)
- The scripts (`review-panel.sh`, `merge.py`) + `sev.schema.json` are committed and MUST NOT be edited during a review cycle. The implementer edits source, never the gate.
- Do NOT re-judge the panel's verdict. A CRITICAL/IMPORTANT that survives the challenge round is fixed or escalated to a human — never argued away by this session.
- Independence: the Claude reviewer runs as a fresh `claude -p` process; challenges are judged by other models. This session never reviews its own code.

## Gate
Exit `0` clean · `1` blocking findings (fix or escalate) · `2` infra (a transient/reviewer failure or fewer than 2 reviewers — NOT clean) · `3` usage.

## Cost
Default = 3 models × 1 diff; the challenge round fires only on cross-model disagreement and only re-asks the non-flagging models about specific findings. No loops.

## Testing
Hermetic, no live model calls (the ~$60 lesson):
- `python3 .claude/skills/review-panel/tests/test_merge.py` — unit tests for the pure `merge.py`. (Run the file directly; `python3 -m unittest <path>` fails because the path isn't a dotted module name.)
- `bash .claude/skills/review-panel/tests/run_integration.sh` — usage gate, adapter-contract presence, and an offline end-to-end (`buggy→1`, `clean→0`, `lone-refuted→0`) driven by stub reviewers via `REVIEW_PANEL_REVIEWER_DIR`.

Set `REVIEW_PANEL_LIVE=1` to additionally exercise the real reviewer CLIs (codex/gemini/claude) — the only path that spends model tokens. Absent CLIs are a clean SKIP.
